/**
 * Outgoing email: the `Mailer` the service sends through, the Resend REST
 * implementation used in production, and the verification email itself.
 *
 * Nothing here logs a recipient, a message body, a code or the API key.
 * Tests inject a recording fake instead of `resendMailer`.
 */
export interface EmailMessage {
  to: string;
  subject: string;
  html: string;
  text: string;
}

/** Sends one message; rejects if the provider didn't accept it. */
export type Mailer = (message: EmailMessage) => Promise<void>;

export const EMAIL_FROM = "Lexerly <no-reply@nineweave.sitebloc.com>";
const RESEND_URL = "https://api.resend.com/emails";
const SEND_TIMEOUT_MS = 10_000;

/** Thrown when the provider rejects or can't be reached. Carries no details. */
export class MailerError extends Error {
  constructor() {
    super("Email provider did not accept the message");
  }
}

/**
 * A Resend-backed mailer, or `null` when no API key is configured (the API
 * then answers 503 on endpoints that send email).
 */
export function resendMailer(
  apiKey: string | undefined,
  fetchImpl: typeof fetch = fetch,
): Mailer | null {
  const key = apiKey?.trim();
  if (!key) return null;
  return async (message) => {
    let res: Response;
    try {
      res = await fetchImpl(RESEND_URL, {
        method: "POST",
        headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
        body: JSON.stringify({ from: EMAIL_FROM, ...message }),
        signal: AbortSignal.timeout(SEND_TIMEOUT_MS),
      });
    } catch {
      throw new MailerError();
    }
    // Drain the body without reading it into logs.
    await res.arrayBuffer().catch(() => undefined);
    if (!res.ok) {
      console.error(`[nineweave] email provider returned HTTP ${res.status}`);
      throw new MailerError();
    }
  };
}

export type CodePurpose = "verify" | "recover";

/** The branded verification / sign-in email (HTML + plain text). */
export function buildCodeEmail(
  to: string,
  code: string,
  purpose: CodePurpose,
  ttlMinutes: number,
): EmailMessage {
  const isRecover = purpose === "recover";
  const subject = isRecover ? "Your Lexerly sign-in code" : "Your Lexerly verification code";
  const lead = isRecover
    ? "Use this code to sign in to your Lexerly account on a new device."
    : "Use this code to verify the email address on your Lexerly account.";
  const text = [
    "LEXERLY",
    "",
    lead,
    "",
    `Your code: ${code}`,
    "",
    `It expires in ${ttlMinutes} minutes.`,
    "If you didn't request this, you can safely ignore this email.",
  ].join("\n");
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="dark">
<title>${subject}</title>
</head>
<body style="margin:0;padding:0;background:#0b0a12;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">Your code expires in ${ttlMinutes} minutes.</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#0b0a12;">
<tr><td align="center" style="padding:40px 16px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:480px;background:#15121f;border:1px solid #3a2f1c;border-radius:16px;">
<tr><td align="center" style="padding:36px 32px 8px;font-family:Georgia,'Times New Roman',serif;font-size:28px;letter-spacing:6px;color:#e8c46a;">LEXERLY</td></tr>
<tr><td align="center" style="padding:0 32px;"><div style="height:1px;width:72px;background:#8a6d2f;"></div></td></tr>
<tr><td align="center" style="padding:24px 32px 8px;font-family:-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;font-size:16px;line-height:24px;color:#efe6cf;">${lead}</td></tr>
<tr><td align="center" style="padding:20px 32px;">
<div style="display:inline-block;padding:18px 28px;background:#0b0a12;border:1px solid #8a6d2f;border-radius:12px;font-family:'SFMono-Regular',Menlo,Consolas,monospace;font-size:38px;font-weight:700;letter-spacing:10px;color:#f5d98b;user-select:all;-webkit-user-select:all;" aria-label="${code}">${code}</div>
</td></tr>
<tr><td align="center" style="padding:8px 32px 32px;font-family:-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;font-size:14px;line-height:22px;color:#b9ae94;">
This code expires in ${ttlMinutes} minutes.<br>
If you didn't request it, you can safely ignore this email.
</td></tr>
</table>
<div style="padding-top:16px;font-family:-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;color:#5f584a;">Sent by Lexerly to ${escapeHtml(to)}</div>
</td></tr>
</table>
</body>
</html>`;
  return { to, subject, html, text };
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
}
