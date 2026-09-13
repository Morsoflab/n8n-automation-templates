 # Lead Intake with n8n Data Table

  A credential-free lead-intake workflow that uses n8n’s built-in Data Tables for validation, duplicate detection, conflict handling, and durable storage.

  ## What it does

  1. Receives lead data through an HTTP POST webhook.
  2. Requires an `Idempotency-Key` header.
  3. Validates and normalizes the submitted fields.
  4. Creates a SHA-256 hash of the normalized payload.
  5. Creates or reuses the `lead_intake_template` Data Table.
  6. Checks whether the idempotency key already exists.
  7. Stores new leads with a `pending` status.
  8. Returns different responses for new, duplicate, conflicting, and invalid requests.

  ## Import

  1. Download `lead-intake-data-table.json`.
  2. Import it into n8n.
  3. Keep the workflow inactive during testing.
  4. Click **Execute workflow** to enable the test webhook.
  5. Copy the test URL from the **Receive Lead** node.

  The workflow creates the required Data Table automatically during the first valid request.

  ## Example request

  ```bash
  curl -i -X POST \
    "YOUR_TEST_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -H "Idempotency-Key: example-lead-001" \
    -d '{
      "name": "Example Lead",
      "email": "lead@example.com",
      "company": "Example Company",
      "message": "We need help connecting our CRM and ERP.",
      "source": "website"
    }'
  ```

  ## Responses

  New lead:

  ```json
  {
    "accepted": true,
    "duplicate": false,
    "leadId": 1
  }
  ```

  Exact duplicate:

  ```json
  {
    "accepted": true,
    "duplicate": true,
    "leadId": 1
  }
  ```

  Conflicting reuse of the same idempotency key:

  ```json
  {
    "accepted": false,
    "error": "IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD"
  }
  ```

  Invalid request:

  ```json
  {
    "accepted": false,
    "errors": [
      "An Idempotency-Key header is required",
      "A valid email is required"
    ]
  }
  ```

  ## Verified test results

  The workflow was imported and tested on n8n with all four paths:

  - New request: HTTP 202
  - Exact duplicate: HTTP 200
  - Conflicting replay: HTTP 409
  - Invalid request: HTTP 400

  ## Production limitations

  The lookup and insertion are separate operations. Under concurrent requests using the same new idempotency key, n8n Data Tables do not provide the atomic uniqueness guarantee available in PostgreSQL.

  Use this version for demonstrations, prototypes, and low-concurrency intake. Use the PostgreSQL version for high-concurrency or business-critical production systems.

  Before production use, also add:

  - Webhook authentication
  - Rate limiting
  - Downstream delivery processing
  - Bounded retries
  - Failure monitoring
  - Manual review for terminal failures
  - Data retention and deletion rules
