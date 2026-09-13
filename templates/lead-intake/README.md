# Webhook Lead Intake

  A credential-free n8n starter workflow that receives a lead through an HTTP POST request, validates the email address, normalizes the fields, and returns an acceptance response.

  ## What it does

  1. Receives lead data through an n8n webhook.
  2. Validates and normalizes the email address.
  3. Normalizes the name, company, message, and source fields.
  4. Adds a lead ID and reception timestamp.
  5. Returns a JSON confirmation.

  This starter does not save or forward the lead. Connect an approved CRM, database, or queue only after reviewing authentication, privacy, retry, and duplicate-handling requirements.

  ## Import

  1. Download `webhook-lead-intake.json`.
  2. Open n8n.
  3. Select **Import from File**.
  4. Import the downloaded JSON file.
  5. Keep the workflow inactive while testing.
  6. Open the **Receive Lead** node and copy its test webhook URL.

  ## Example request

  Replace `YOUR_TEST_WEBHOOK_URL` with the test URL provided by n8n.

  ```bash
  curl -X POST "YOUR_TEST_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "Example Lead",
      "email": "lead@example.com",
      "company": "Example Company",
      "message": "We need help connecting our CRM and ERP.",
      "source": "website"
    }'
  ```

  ## Expected response

  ```json
  {
    "accepted": true,
    "leadId": "execution-id"
  }
  ```

  ## Production checklist

  - Protect the webhook against unauthorized submissions.
  - Add rate limiting at the proxy or application layer.
  - Define an idempotency key and duplicate policy.
  - Store credentials only in n8n credentials or environment variables.
  - Add bounded retries and a manual review path for terminal failures.
  - Avoid logging unnecessary personal data.
  - Define retention and deletion rules.
  - Test recovery before activation.
