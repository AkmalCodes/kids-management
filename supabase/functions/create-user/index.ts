// Director-only account provisioning.
//
// Creating an account for someone else (setting their email, sending an
// invite) requires Supabase's admin API, which needs the service role key.
// That key must never reach the Flutter app -- it bypasses every RLS
// policy in the database. So this runs here instead: the app calls this
// function with the director's own session (Supabase's client SDK attaches
// that automatically), this function verifies the caller is really a
// director using their JWT, and only then uses the service role key to do
// the privileged part.
//
// Request body:
//   { "role": "teacher", "email": string, "name": string, "phone"?: string }
//   { "role": "parent", "email": string, "name": string, "phone"?: string, "childId": string }
//     -- also links the new parent to childId in children_parents.
//
// Response: { "userId": string } on success, or { "error": string } (4xx/5xx).

import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Missing Authorization header" }, 401);
  }

  // A client scoped to the caller's own JWT -- RLS applies as normal, so
  // this can only ever read the caller's own profile row, never anyone
  // else's. That's enough to confirm their role.
  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const {
    data: { user: caller },
  } = await callerClient.auth.getUser();
  if (!caller) {
    return jsonResponse({ error: "Not authenticated" }, 401);
  }

  const { data: callerProfile, error: profileError } = await callerClient
    .from("profiles")
    .select("role, center_id")
    .eq("id", caller.id)
    .single();
  if (profileError || callerProfile?.role !== "director") {
    return jsonResponse({ error: "Only directors can create accounts" }, 403);
  }

  let body: {
    role?: string;
    email?: string;
    name?: string;
    phone?: string;
    childId?: string;
  };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const { role, email, name, phone, childId } = body;
  if (role !== "teacher" && role !== "parent") {
    return jsonResponse({ error: "role must be 'teacher' or 'parent'" }, 400);
  }
  if (!email || !name) {
    return jsonResponse({ error: "email and name are required" }, 400);
  }
  if (role === "parent" && !childId) {
    return jsonResponse({ error: "childId is required when role is 'parent'" }, 400);
  }

  // Security (M5): a parent link must target a child in the CALLER's own
  // center. Without this, a director could link a parent to any child id in
  // the database (the admin client below bypasses RLS), leaking across
  // centers. Checked with the caller's own RLS-scoped client.
  if (role === "parent") {
    const { data: child, error: childError } = await callerClient
      .from("children")
      .select("center_id")
      .eq("id", childId)
      .single();
    if (childError || !child) {
      return jsonResponse({ error: "Child not found" }, 404);
    }
    if (child.center_id !== callerProfile.center_id) {
      return jsonResponse({ error: "Child is not in your center" }, 403);
    }
  }

  // Privileged client -- only ever touches what this function explicitly
  // does below, never anything driven by unvalidated request input.
  const adminClient = createClient(supabaseUrl, serviceRoleKey);

  // generateLink creates the auth user and hands back the invite URL, but
  // -- unlike inviteUserByEmail -- does NOT send any email itself; we send
  // it ourselves below via Mailgun's API. Switched away from
  // inviteUserByEmail because Supabase's own SMTP-relay mailer was
  // silently stripping the HTML down to plain text, dropping the link
  // (recipients saw the words "Accept invitation" with no href).
  // redirectTo makes that link deep-link back into the app (see the
  // matching scheme in AndroidManifest.xml / Info.plist) instead of the
  // project's default Site URL.
  const { data: linkData, error: linkError } = await adminClient.auth.admin
    .generateLink({
      type: "invite",
      email,
      options: {
        redirectTo: "com.example.kids_management://login-callback/",
      },
    });
  if (linkError || !linkData?.user) {
    return jsonResponse({ error: linkError?.message ?? "Invite failed" }, 400);
  }
  const newUserId = linkData.user.id;

  // Build the verify URL ourselves instead of trusting action_link's
  // embedded redirect_to -- in testing, the redirectTo option above didn't
  // reliably make it through the SDK into action_link (it silently fell
  // back to the project's default Site URL, http://localhost:3000,
  // instead of our app's scheme). hashed_token + verification_type are
  // exactly what action_link is built from (per GoTrue's own doc comment:
  // auth/v1/verify?type={verification_type}&token={hashed_token}&redirect_to={redirect_to}),
  // so reconstructing it here guarantees our redirect always applies.
  const props = linkData.properties;
  const actionLink = `${supabaseUrl}/auth/v1/verify?type=${props.verification_type}&token=${props.hashed_token}&redirect_to=${
    encodeURIComponent("com.example.kids_management://login-callback/")
  }`;

  const emailError = await sendInviteEmail(email, actionLink);
  if (emailError) {
    // The auth user + link already exist at this point -- don't leave the
    // director thinking nothing happened. A retry would just mint a
    // second (still valid) link rather than fix anything, so surface this
    // distinctly instead of the generic "Invite failed" above.
    return jsonResponse({ error: `Account created but email failed to send: ${emailError}` }, 502);
  }

  const { error: insertProfileError } = await adminClient.from("profiles").insert({
    id: newUserId,
    role,
    name,
    phone: phone ?? "",
    // Denormalized so a director can display this person's email later
    // (auth.users isn't readable cross-user from the client).
    email,
    center_id: callerProfile.center_id,
    // Forces the set-password screen on first entry (they were invited,
    // so they've never chosen a password).
    must_set_password: true,
    created_by: caller.id,
    updated_by: caller.id,
  });
  if (insertProfileError) {
    // Best-effort cleanup so a failed profile insert doesn't leave a
    // dangling auth user with no matching profile row.
    await adminClient.auth.admin.deleteUser(newUserId);
    return jsonResponse({ error: insertProfileError.message }, 500);
  }

  if (role === "parent") {
    const { error: linkError } = await adminClient
      .from("children_parents")
      .insert({ child_id: childId, parent_id: newUserId });
    if (linkError) {
      return jsonResponse({ error: linkError.message }, 500);
    }
  }

  return jsonResponse({ userId: newUserId }, 200);
});

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// Sends the invite email ourselves via Mailgun's HTTP API (see the comment
// above generateLink for why this replaced Supabase's SMTP relay).
// Returns null on success, or an error message string on failure.
async function sendInviteEmail(toEmail: string, actionLink: string): Promise<string | null> {
  const mailgunApiKey = Deno.env.get("MAILGUN_API_KEY")!;
  const mailgunDomain = Deno.env.get("MAILGUN_DOMAIN")!;

  const html = `
    <h2>You've been invited</h2>
    <p>You've been invited to create a Childcare Manager account. Follow the link below to accept and set your password.</p>
    <p><a href="${actionLink}">Accept invitation</a></p>
  `;

  const form = new FormData();
  form.append("from", `Childcare Manager <no-reply@${mailgunDomain}>`);
  form.append("to", toEmail);
  form.append("subject", "You've been invited");
  form.append("html", html);
  // Mailgun's click-tracking is on by default: it rewrites every <a href>
  // to go through a Mailgun tracking subdomain first, then redirects to
  // the real link. Gmail's spam filter distrusts that redirect hop on an
  // unfamiliar domain and was stripping the link entirely. Turning
  // tracking off keeps our actual actionLink verbatim in the HTML.
  form.append("o:tracking-clicks", "no");

  const response = await fetch(`https://api.mailgun.net/v3/${mailgunDomain}/messages`, {
    method: "POST",
    headers: {
      // Mailgun HTTP API uses Basic auth: username is always the literal
      // string "api", password is the private API key.
      Authorization: `Basic ${btoa(`api:${mailgunApiKey}`)}`,
    },
    body: form,
  });

  if (!response.ok) {
    const body = await response.text();
    return `Mailgun ${response.status}: ${body}`;
  }
  return null;
}
