import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authorization = request.headers.get("Authorization") ?? "";
    const callerClient = createClient(url, anonKey, { global: { headers: { Authorization: authorization } } });
    const adminClient = createClient(url, serviceKey);

    const { data: authData, error: authError } = await callerClient.auth.getUser();
    if (authError || !authData.user) throw new Error("Authentication required.");

    const { data: caller } = await adminClient.from("profiles").select("role, active").eq("id", authData.user.id).single();
    if (caller?.role !== "owner" || !caller.active) throw new Error("Owner access required.");

    const body = await request.json();
    if (body.action === "delete") {
      const { error } = await adminClient.auth.admin.deleteUser(body.user_id);
      if (error) throw error;
      return json({ deleted: true });
    }

    if (!["manager", "counter"].includes(body.role)) throw new Error("Invalid staff role.");
    const digits = String(body.phone ?? "").replace(/\D/g, "");
    if (digits.length < 10) throw new Error("A valid staff phone is required.");
    const email = `${digits}@staff.mashbash.app`;

    const { data: created, error: createError } = await adminClient.auth.admin.createUser({
      email,
      password: body.password,
      email_confirm: true,
      user_metadata: { name: body.name, phone: body.phone, staff: true },
    });
    if (createError || !created.user) throw createError ?? new Error("Staff account could not be created.");

    const { error: profileError } = await adminClient.from("profiles").upsert({
      id: created.user.id,
      name: body.name,
      phone: body.phone,
      address: "Mashbash restaurant",
      email,
      role: body.role,
      active: true,
    });
    if (profileError) throw profileError;

    const permissions = body.permissions ?? {};
    const { error: permissionError } = await adminClient.from("staff_permissions").upsert({
      profile_id: created.user.id,
      view_orders: permissions.viewOrders === true,
      update_order_status: permissions.updateOrderStatus === true,
      manage_menu: permissions.manageMenu === true,
      manage_deals: permissions.manageDeals === true,
      view_reports: permissions.viewReports === true,
    });
    if (permissionError) throw permissionError;

    return json({ id: created.user.id });
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
