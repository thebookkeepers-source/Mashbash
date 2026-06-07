import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";

type Profile = { id: string; role: string };
type StaffProfile = Profile & { staff_permissions: { view_orders?: boolean } | Array<{ view_orders?: boolean }> | null };
type Order = {
  id: string;
  customer_id: string;
  customer_name: string;
  assigned_rider_id: string | null;
  status: string;
  created_at: string;
};
type DeviceToken = { id: string; token: string; role: string };
type ServiceAccount = { project_id: string; client_email: string; private_key: string };

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== "POST") return json({ ok: false, error: "Method not allowed." }, 405);

    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const anonKey = requiredEnv("SUPABASE_ANON_KEY");
    const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
    const authorization = req.headers.get("Authorization");
    if (!authorization) return json({ ok: false, error: "Authentication required." }, 401);

    const callerClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authorization } } });
    const admin = createClient(supabaseUrl, serviceRoleKey);
    const { data: authData, error: authError } = await callerClient.auth.getUser();
    if (authError || !authData.user) return json({ ok: false, error: "Authentication required." }, 401);

    const { data: profile } = await admin.from("profiles").select("id, role").eq("id", authData.user.id).eq("active", true).single<Profile>();
    if (!profile) return json({ ok: false, error: "Active profile required." }, 403);

    const request = await req.json();
    const event = String(request.event ?? "");
    const userIds = new Set<string>();
    let title = "";
    let body = "";
    let orderId = "";
    let order: Order | null = null;

    if (event === "test") {
      title = "Mashbash test notification";
      body = "Push notifications are working on this device.";
      userIds.add(profile.id);
    } else if (event === "custom") {
      if (profile.role !== "owner") return json({ ok: false, error: "Owner access required." }, 403);
      title = cleanText(request.title, 80);
      body = cleanText(request.body, 220);
      if (!title || !body) return json({ ok: false, error: "A title and message are required." }, 400);
      if (request.all_customers === true) {
        await addActiveProfiles(admin, userIds, ["customer"]);
      } else if (Array.isArray(request.user_ids)) {
        request.user_ids.slice(0, 100).forEach((id: unknown) => userIds.add(String(id)));
      }
    } else {
      orderId = String(request.order_id ?? "");
      const { data: orderRow } = await admin
        .from("orders")
        .select("id, customer_id, customer_name, assigned_rider_id, status, created_at")
        .eq("id", orderId)
        .single<Order>();
      order = orderRow;
      if (!order) return json({ ok: false, error: "Order not found." }, 404);

      const assignedRider = profile.role === "rider" && order.assigned_rider_id === profile.id;
      if (event === "order_placed") {
        if (profile.id !== order.customer_id) return json({ ok: false, error: "Order access denied." }, 403);
        title = "Order placed";
        body = `Your Mashbash order #${shortId(order.id)} was received.`;
        userIds.add(order.customer_id);
        const settings = await notificationSettings(admin);
        if (settings.new_order_notifications !== false) await addOrderStaff(admin, userIds);
      } else if (event === "order_status") {
        if (!assignedRider && !(await staffHasPermission(admin, profile, "update_order_status"))) {
          return json({ ok: false, error: "Order access denied." }, 403);
        }
        const message = statusMessage(order);
        title = message.title;
        body = message.body;
        const settings = await notificationSettings(admin);
        if (settings.order_status_notifications !== false) userIds.add(order.customer_id);
        if (order.status === "ready_for_delivery" || order.status === "delivered" || order.status === "cancelled") {
          await addOrderStaff(admin, userIds);
        }
        if (order.status === "cancelled" && order.assigned_rider_id) userIds.add(order.assigned_rider_id);
      } else if (event === "rider_assigned") {
        if (!(await staffHasPermission(admin, profile, "assign_riders"))) {
          return json({ ok: false, error: "Order access denied." }, 403);
        }
        title = "New delivery assigned";
        body = `Mashbash order #${shortId(order.id)} is ready for delivery.`;
        userIds.add(order.customer_id);
        if (order.assigned_rider_id) userIds.add(order.assigned_rider_id);
        await addOrderStaff(admin, userIds);
      } else if (event === "pending_order") {
        if (!(await staffHasPermission(admin, profile, "view_orders")) || !["received", "accepted", "preparing"].includes(order.status)) {
          return json({ ok: false, error: "Order access denied." }, 403);
        }
        const settings = await notificationSettings(admin);
        const pendingMinutes = Number(settings.pending_alert_minutes ?? 15);
        if (Date.now() - new Date(order.created_at).getTime() < pendingMinutes * 60_000) {
          return json({ ok: true, sent: 0, skipped: "not_due" });
        }
        title = "Order waiting too long";
        body = `Order #${shortId(order.id)} has been pending for more than ${pendingMinutes} minutes.`;
        await addOrderStaff(admin, userIds);
      } else {
        return json({ ok: false, error: "Unsupported notification event." }, 400);
      }
    }

    const tokens = await activeTokens(admin, [...userIds]);
    if (tokens.length === 0) return json({ ok: true, sent: 0, failed: 0, deactivated: 0, no_active_tokens: true });

    const serviceAccount = firebaseServiceAccount();
    const accessToken = await firebaseAccessToken(serviceAccount);
    let eventKey = "";
    if (order) {
      eventKey = event === "order_status" ? `${event}:${order.status}` : event;
      const { error: eventError } = await admin.from("notification_events").insert({ order_id: order.id, event_key: eventKey });
      if (eventError?.code === "23505") return json({ ok: true, sent: 0, failed: 0, deactivated: 0, duplicate: true });
      if (eventError) throw eventError;
    }

    let sent = 0;
    let failed = 0;
    let deactivated = 0;
    for (const device of tokens) {
      const recipient = recipientMessage(event, device.role, order, title, body);
      const response = await fetch(`https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`, {
        method: "POST",
        headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            token: device.token,
            notification: recipient,
            data: { type: event, event, order_id: orderId, target_role: device.role },
            android: {
              priority: "HIGH",
              notification: { color: "#8B0000", channel_id: "mashbash_orders", sound: "default" },
            },
          },
        }),
      });
      if (response.ok) {
        sent++;
        continue;
      }

      failed++;
      const failure = await response.text();
      const invalid = response.status === 404 || failure.includes("UNREGISTERED") || failure.includes("registration-token-not-registered");
      console.error("FCM send failed", { token_id: device.id, role: device.role, status: response.status, invalid });
      if (invalid) {
        await admin.from("device_tokens").update({ is_active: false, updated_at: new Date().toISOString() }).eq("id", device.id);
        deactivated++;
      }
    }

    if (order && sent === 0) {
      await admin.from("notification_events").delete().eq("order_id", order.id).eq("event_key", eventKey);
    }
    const result = { ok: sent > 0, sent, failed, deactivated, recipients: tokens.length };
    return sent > 0 ? json(result) : json({ ...result, error: "Notification delivery is temporarily unavailable." }, 502);
  } catch (error) {
    console.error("send-notification failed", error instanceof Error ? error.message : "unknown_error");
    return json({ ok: false, error: "Notification delivery could not be completed." }, 500);
  }
});

function cleanText(value: unknown, max: number) {
  return String(value ?? "").trim().slice(0, max);
}

async function notificationSettings(admin: SupabaseClient) {
  const { data } = await admin
    .from("app_settings")
    .select("new_order_notifications, order_status_notifications, pending_alert_minutes")
    .eq("id", "main")
    .maybeSingle();
  return data ?? { new_order_notifications: true, order_status_notifications: true, pending_alert_minutes: 15 };
}

async function addActiveProfiles(admin: SupabaseClient, userIds: Set<string>, roles: string[]) {
  const { data, error } = await admin.from("profiles").select("id").eq("active", true).in("role", roles);
  if (error) throw error;
  data?.forEach((row) => userIds.add(String(row.id)));
}

async function addOrderStaff(admin: SupabaseClient, userIds: Set<string>) {
  const { data, error } = await admin
    .from("profiles")
    .select("id, role, staff_permissions(view_orders)")
    .eq("active", true)
    .in("role", ["owner", "manager", "counter"]);
  if (error) throw error;
  (data as StaffProfile[] | null)?.forEach((staff) => {
    const permission = Array.isArray(staff.staff_permissions) ? staff.staff_permissions[0] : staff.staff_permissions;
    if (staff.role === "owner" || permission?.view_orders === true) userIds.add(staff.id);
  });
}

async function staffHasPermission(admin: SupabaseClient, profile: Profile, permission: string) {
  if (profile.role === "owner") return true;
  if (!["manager", "counter"].includes(profile.role)) return false;
  const { data, error } = await admin.from("staff_permissions").select(permission).eq("profile_id", profile.id).maybeSingle();
  if (error) throw error;
  return data?.[permission] === true;
}

async function activeTokens(admin: SupabaseClient, userIds: string[]) {
  if (userIds.length === 0) return [] as DeviceToken[];
  const { data, error } = await admin.from("device_tokens").select("id, token, role").eq("is_active", true).in("user_id", userIds);
  if (error) throw error;
  return (data ?? []) as DeviceToken[];
}

function recipientMessage(event: string, role: string, order: Order | null, title: string, body: string) {
  if (event === "order_placed" && role !== "customer" && order) {
    return { title: "New order received", body: `${order.customer_name} placed order #${shortId(order.id)}.` };
  }
  if (event === "rider_assigned" && role === "rider" && order) {
    return { title: "New delivery assigned", body: `Mashbash order #${shortId(order.id)} is ready for delivery.` };
  }
  if (event === "rider_assigned" && role !== "rider" && order) {
    return { title: "Rider assigned", body: `A rider was assigned to order #${shortId(order.id)}.` };
  }
  if (event === "order_status" && role !== "customer" && order?.status === "delivered") {
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

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not configured.`);
  return value;
}

function firebaseServiceAccount(): ServiceAccount {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (raw) {
    const parsed = JSON.parse(raw) as Partial<ServiceAccount>;
    if (parsed.project_id && parsed.client_email && parsed.private_key) {
      return {
        project_id: parsed.project_id,
        client_email: parsed.client_email,
        private_key: parsed.private_key.replaceAll("\\n", "\n"),
      };
    }
    throw new Error("FIREBASE_SERVICE_ACCOUNT_JSON is invalid.");
  }

  const projectId = Deno.env.get("FIREBASE_PROJECT_ID");
  const clientEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL");
  const privateKey = Deno.env.get("FIREBASE_PRIVATE_KEY")?.replaceAll("\\n", "\n");
  if (!projectId || !clientEmail || !privateKey) throw new Error("Firebase service account secret is not configured.");
  return { project_id: projectId, client_email: clientEmail, private_key: privateKey };
}

async function firebaseAccessToken(serviceAccount: ServiceAccount) {
  const key = await importPKCS8(serviceAccount.private_key, "RS256");
  const assertion = await new SignJWT({ scope: "https://www.googleapis.com/auth/firebase.messaging" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(serviceAccount.client_email)
    .setSubject(serviceAccount.client_email)
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
