import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !anonKey || !serviceKey) throw new Error("Server configuration is incomplete.");

    const authorization = request.headers.get("Authorization") ?? "";
    const callerClient = createClient(url, anonKey, { global: { headers: { Authorization: authorization } } });
    const adminClient = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });

    const { data: authData, error: authError } = await callerClient.auth.getUser();
    if (authError || !authData.user) throw new Error("Authentication required.");
    const { data: caller } = await adminClient.from("profiles").select("role, active").eq("id", authData.user.id).single();
    if (caller?.role !== "owner" || !caller.active) throw new Error("Owner access required.");

    const body = await request.json();
    const action = String(body.action ?? "create");
    if (["disable", "enable", "delete", "update"].includes(action)) {
      const { data: target } = await adminClient.from("profiles").select("role").eq("id", body.user_id).single();
      if (!target || !["manager", "counter", "rider"].includes(target.role)) throw new Error("Only staff accounts can be changed here.");
    }
    if (["disable", "enable"].includes(action)) {
      const { error } = await adminClient.from("profiles").update({ active: action === "enable" }).eq("id", body.user_id).in("role", ["manager", "counter", "rider"]);
      if (error) throw error;
      return json({ updated: true });
    }
    if (action === "delete") {
      const { error } = await adminClient.auth.admin.deleteUser(body.user_id);
      if (error) throw error;
      return json({ deleted: true });
    }

    if (!["manager", "counter", "rider"].includes(body.role)) throw new Error("Choose Manager, Counter, or Rider.");
    const digits = String(body.phone ?? "").replace(/\D/g, "");
    if (digits.length < 10 || digits.length > 15) throw new Error("Enter a valid staff mobile number.");
    if (String(body.name ?? "").trim().length < 2) throw new Error("Enter the staff member's full name.");
    if (action !== "update" && String(body.password ?? "").length < 8) throw new Error("Password must contain at least 8 characters.");
    if (action === "update" && String(body.password ?? "").length > 0 && String(body.password).length < 8) throw new Error("A new password must contain at least 8 characters.");
    const email = `${digits}@staff.mashbash.app`;
    const permissions = body.permissions ?? {};
    const counter = body.role === "counter";

    if (action === "update") {
      const authUpdates: Record<string, unknown> = { email, email_confirm: true, user_metadata: { name: String(body.name).trim(), phone: body.phone, staff: true, role: body.role } };
      if (String(body.password ?? "").length > 0) authUpdates.password = body.password;
      const { error: authUpdateError } = await adminClient.auth.admin.updateUserById(body.user_id, authUpdates);
      if (authUpdateError) throw authUpdateError;
      const { error: profileUpdateError } = await adminClient.from("profiles").update({ name: String(body.name).trim(), phone: body.phone, email, role: body.role }).eq("id", body.user_id);
      if (profileUpdateError) throw profileUpdateError;
      if (body.role === "rider") {
        await adminClient.from("staff_permissions").delete().eq("profile_id", body.user_id);
      } else {
        const { error: permissionUpdateError } = await adminClient.from("staff_permissions").upsert({
          profile_id: body.user_id,
          view_orders: counter || permissions.viewOrders === true,
          update_order_status: counter || permissions.updateOrderStatus === true,
          assign_riders: counter || permissions.assignRiders === true,
          manage_menu: permissions.manageMenu === true,
          manage_deals: permissions.manageDeals === true,
          manage_slides: permissions.manageSlides === true,
          view_reports: permissions.viewReports === true,
        });
        if (permissionUpdateError) throw permissionUpdateError;
      }
      return json({ updated: true });
    }

    const { data: created, error: createError } = await adminClient.auth.admin.createUser({
      email,
      password: body.password,
      email_confirm: true,
      user_metadata: { name: String(body.name).trim(), phone: body.phone, staff: true, role: body.role },
    });
    if (createError || !created.user) {
      if (createError?.message.toLowerCase().includes("already")) throw new Error("A staff account already uses this mobile number.");
      throw new Error("Staff account could not be created.");
    }

    try {
      const { error: profileError } = await adminClient.from("profiles").upsert({
        id: created.user.id,
        name: String(body.name).trim(),
        phone: body.phone,
        address: "Mashbash restaurant",
        email,
        role: body.role,
        active: true,
        rider_available: false,
      });
      if (profileError) throw profileError;

      if (body.role !== "rider") {
        const { error: permissionError } = await adminClient.from("staff_permissions").upsert({
          profile_id: created.user.id,
          view_orders: counter || permissions.viewOrders === true,
          update_order_status: counter || permissions.updateOrderStatus === true,
          assign_riders: counter || permissions.assignRiders === true,
          manage_menu: permissions.manageMenu === true,
          manage_deals: permissions.manageDeals === true,
          manage_slides: permissions.manageSlides === true,
          view_reports: permissions.viewReports === true,
        });
        if (permissionError) throw permissionError;
      }
    } catch (error) {
      await adminClient.auth.admin.deleteUser(created.user.id);
      throw error;
    }

    return json({ id: created.user.id, message: `${body.role} account created.` });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Request failed." }, 400);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
