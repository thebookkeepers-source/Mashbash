import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";

type Profile = { id: string; role: string };
type Order = {
  id: string;
  customer_id: string;
  customer_name: string;
  assigned_rider_id: string | null;
  status: string;
};
type DeviceToken = { id: string; token: string; role: string };

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== "POST") return json({ error: "Method not allowed." }, 405);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authorization = req.headers.get("Authorization");
    if (!authorization) return json({ error: "Authentication required." }, 401);

    const callerClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authorization } } });
    const admin = createClient(supabaseUrl, serviceRoleKey);
    const { data: authData, error: authError } = await callerClient.auth.getUser();
    if (authError || !authData.user) return json({ error: "Authentication required." }, 401);

    const { data: profile } = await admin.from("profiles").select("id, role").eq("id", authData.user.id).eq("active", true).single<Profile>();
    if (!profile) return json({ error: "Active profile required." }, 403);

    const request = await req.json();
    const event = String(request.event ?? "");
    const userIds = new Set<string>();
    const roles = new Set<string>();
    let title = "";
    let body = "";
    let orderId = "";
    let order: Order | null = null;

    if (event === "custom") {
      if (profile.role !== "owner") return json({ error: "Owner access required." }, 403);
      title = cleanText(request.title, 80);
      body = cleanText(request.body, 220);
      if (!title || !body) return json({ error: "A title and message are required." }, 400);
      if (request.all_customers === true) {
        roles.add("customer");
      } else if (Array.isArray(request.user_ids)) {
        request.user_ids.slice(0, 100).forEach((id: unknown) => userIds.add(String(id)));
      }
    } else {
      orderId = String(request.order_id ?? "");
      const { data: orderRow } = await admin
        .from("orders")
        .select("id, customer_id, customer_name, assigned_rider_id, status")
        .eq("id", orderId)
        .single<Order>();
      order = orderRow;
      if (!order) return json({ error: "Order not found." }, 404);

      const staff = ["owner", "manager", "counter"].includes(profile.role);
      const assignedRider = profile.role === "rider" && order.assigned_rider_id === profile.id;
      if (event === "order_placed") {
        if (profile.id !== order.customer_id) return json({ error: "Order access denied." }, 403);
        title = "Order placed";
        body = `Your Mashbash order #${shortId(order.id)} was received.`;
        userIds.add(order.customer_id);
        const { data: settings } = await admin.from("app_settings").select("new_order_notifications").eq("id", "main").maybeSingle();
        if (settings?.new_order_notifications !== false) ["owner", "manager", "counter"].forEach((role) => roles.add(role));
      } else if (event === "order_status") {
        if (!staff && !assignedRider) return json({ error: "Order access denied." }, 403);
        const message = statusMessage(order);
        title = message.title;
        body = message.body;
        userIds.add(order.customer_id);
        if (order.status === "ready_for_delivery") ["owner", "manager", "counter"].forEach((role) => roles.add(role));
        if (order.status === "delivered") roles.add("owner");
        if (order.status === "cancelled") {
          ["owner", "manager", "counter"].forEach((role) => roles.add(role));
          if (order.assigned_rider_id) userIds.add(order.assigned_rider_id);
        }
      } else if (event === "rider_assigned") {
        if (!staff) return json({ error: "Order access denied." }, 403);
        title = "New delivery assigned";
        body = `Mashbash order #${shortId(order.id)} is ready for delivery.`;
        userIds.add(order.customer_id);
        if (order.assigned_rider_id) userIds.add(order.assigned_rider_id);
        ["owner", "manager", "counter"].forEach((role) => roles.add(role));
      } else {
        return json({ error: "Unsupported notification event." }, 400);
      }
    }

    const tokens = new Map<string, DeviceToken>();
    if (userIds.size > 0) {
      const { data } = await admin.from("device_tokens").select("id, token, role").eq("is_active", true).in("user_id", [...userIds]);
      data?.forEach((row) => tokens.set(row.id, row as DeviceToken));
    }
    if (roles.size > 0) {
      const { data } = await admin.from("device_tokens").select("id, token, role").eq("is_active", true).in("role", [...roles]);
      data?.forEach((row) => tokens.set(row.id, row as DeviceToken));
    }

    if (tokens.size === 0) return json({ sent: 0 });
    const accessToken = await firebaseAccessToken();
    let sent = 0;
    for (const [id, device] of tokens) {
      const recipient = recipientMessage(event, device.role, order, title, body);
      const response = await fetch(`https://fcm.googleapis.com/v1/projects/${firebaseProjectId()}/messages:send`, {
        method: "POST",
        headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            token: device.token,
            notification: recipient,
            data: { event, order_id: orderId },
            android: { priority: "high", notification: { color: "#8B0000", channel_id: "mashbash_orders" } },
          },
        }),
      });
      if (response.ok) {
        sent++;
      } else {
        const failure = await response.text();
        console.error("FCM send failed", response.status, failure);
        if (response.status === 404 || failure.includes("UNREGISTERED")) {
          await admin.from("device_tokens").update({ is_active: false, updated_at: new Date().toISOString() }).eq("id", id);
        }
      }
    }
    return json({ sent });
  } catch (error) {
    console.error("send-notification failed", error);
    return json({ error: "Notification delivery could not be completed." }, 500);
  }
});

function cleanText(value: unknown, max: number) {
  return String(value ?? "").trim().slice(0, max);
}

function recipientMessage(event: string, role: string, order: Order | null, title: string, body: string) {
  if (event === "order_placed" && role !== "customer" && order) {
    return { title: "New order received", body: `${order.customer_name} placed order #${shortId(order.id)}.` };
  }
  if (event === "rider_assigned" && role !== "rider" && order) {
    return { title: "Rider assigned", body: `A rider was assigned to order #${shortId(order.id)}.` };
  }
  if (event === "order_status" && role === "owner" && order?.status === "delivered") {
    return { title: "Rider delivered order", body: `Order #${shortId(order.id)} was completed.` };
  }
  return { title, body };
}

function shortId(id: string) {
  return id.slice(0, 8).toUpperCase();
}

function statusMessage(order: Order) {
  const suffix = `Order #${shortId(order.id)}`;
  switch (order.status) {
    case "accepted":
      return { title: "Order accepted", body: `${suffix} has been accepted by Mashbash.` };
    case "preparing":
      return { title: "Order preparing", body: `${suffix} is being prepared.` };
    case "ready_for_delivery":
      return { title: "Ready for delivery", body: `${suffix} is ready for rider assignment.` };
    case "assigned_to_rider":
      return { title: "Rider assigned", body: `${suffix} has been assigned to a rider.` };
    case "out_for_delivery":
      return { title: "Out for delivery", body: `${suffix} is on the way.` };
    case "delivered":
      return { title: "Order completed", body: `${suffix} was delivered. Meet.Eat.Repeat.` };
    case "cancelled":
      return { title: "Order cancelled", body: `${suffix} was cancelled.` };
    default:
      return { title: "Order update", body: `${suffix} has a new update.` };
  }
}

function firebaseProjectId() {
  const value = Deno.env.get("FIREBASE_PROJECT_ID");
  if (!value) throw new Error("FIREBASE_PROJECT_ID is not configured.");
  return value;
}

async function firebaseAccessToken() {
  const clientEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL");
  const privateKey = Deno.env.get("FIREBASE_PRIVATE_KEY")?.replaceAll("\\n", "\n");
  if (!clientEmail || !privateKey) throw new Error("Firebase service account secrets are not configured.");
  const key = await importPKCS8(privateKey, "RS256");
  const assertion = await new SignJWT({ scope: "https://www.googleapis.com/auth/firebase.messaging" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(clientEmail)
    .setSubject(clientEmail)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(key);
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!response.ok) throw new Error("Firebase OAuth token request failed.");
  const payload = await response.json();
  return payload.access_token as string;
}
