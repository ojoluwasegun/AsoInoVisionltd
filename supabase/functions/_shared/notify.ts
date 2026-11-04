// Sends a notification by email (Resend) and WhatsApp (Meta WhatsApp Business Cloud API).
// Each channel is skipped quietly if its secrets are not set, so the forms keep working while you set them up.
export async function notify(subject: string, text: string) {
  const key = Deno.env.get('RESEND_API_KEY');
  if (key) {
    const r = await fetch('https://api.resend.com/emails', {
      method: 'POST', headers: { Authorization: `Bearer ${key}`, 'content-type': 'application/json' },
      body: JSON.stringify({ from: Deno.env.get('MAIL_FROM') ?? 'ASO INOVISION <onboarding@resend.dev>', to: [Deno.env.get('NOTIFY_EMAIL') ?? 'asoinovisionpro@gmail.com'], subject, text }),
    });
    if (!r.ok) console.error('email failed', await r.text());
  }
  const token = Deno.env.get('WHATSAPP_TOKEN'), phoneId = Deno.env.get('WHATSAPP_PHONE_ID');
  if (token && phoneId) {
    // Messages we start must use an approved template with one body variable, and the variable cannot contain line breaks.
    const r = await fetch(`https://graph.facebook.com/v20.0/${phoneId}/messages`, {
      method: 'POST', headers: { Authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ messaging_product: 'whatsapp', to: Deno.env.get('NOTIFY_WHATSAPP') ?? '2349068290425', type: 'template',
        template: { name: Deno.env.get('WHATSAPP_TEMPLATE') ?? 'new_enquiry', language: { code: 'en' },
          components: [{ type: 'body', parameters: [{ type: 'text', text: `${subject}: ${text}`.replace(/\s*\n\s*/g, ' | ').slice(0, 900) }] }] } }),
    });
    if (!r.ok) console.error('whatsapp failed', await r.text());
  }
}
