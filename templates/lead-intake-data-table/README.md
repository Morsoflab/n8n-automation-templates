 # Lead Intake with n8n Data Table

  A credential-free lead-intake workflow that uses n8n’s built-in Data Tables for validation, request idempotency, possible duplicate review, conflict handling, and durable storage.

  ## What it does

  1. Receives lead data through an HTTP POST webhook.
  2. Requires an `Idempotency-Key` header.
  3. Validates the request and normalizes email and optional phone fields.
  4. Creates a SHA-256 hash of the normalized payload.
  5. Creates or reuses the `lead_intake_template` Data Table.
  6. Checks whether the idempotency key already exists.
  7. For a new key, checks existing rows for the same normalized email or the same non-empty normalized phone.
  8. Stores every new submission. Likely person-level duplicates use `manual_review`; other leads use `pending`.
  9. Records the possible matching row and its email, phone, name, and company signals without merging or rejecting the submission.
  10. Returns the existing responses for new, duplicate, conflicting, and invalid requests.

  ## Import

  1. Download `lead-intake-data-table.json`.
  2. Import it into n8n.
  3. Keep the workflow inactive during testing.
  4. Click **Execute workflow** to enable the test webhook.
  5. Copy the test URL from the **Receive Lead** node.

  The workflow creates the required Data Table automatically during the first valid request.

  Existing imports need three string columns added to `lead_intake_template` before the updated workflow runs: `phone`, `possible_duplicate_of`, and `duplicate_signals`. Existing rows can leave them empty. Fresh imports create all three columns automatically.

  ## Example request

  ```bash
  curl -i -X POST \
    "YOUR_TEST_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -H "Idempotency-Key: example-lead-001" \
    -d '{
      "name": "Example Lead",
      "email": "lead@example.com",
      "phone": "+49 30 1234 5678",
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

  Email comparison is case-insensitive after trimming whitespace. Phone comparison removes non-digits and treats an international `00` prefix like `+`; it does not infer a country code.

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

  The updated workflow was imported and tested in n8n on 2026-09-15:

  - New request: HTTP 202; created lead 3 with `status=pending`.
  - Exact replay: HTTP 200; returned lead 3 without inserting a new row.
  - Same key with changed payload: HTTP 409.
  - Same normalized email with a new key: HTTP 202; created lead 4 with `status=manual_review`, `possible_duplicate_of=3`, and `duplicate_signals=email,phone,name,company`.
  - Same normalized phone with a different email and key: HTTP 202; created lead 5 with `status=manual_review`, `possible_duplicate_of=3`, and `duplicate_signals=phone,name,company`.
  - Different contact details: HTTP 202; created lead 6 with `status=pending` and empty duplicate fields.
  - Missing phone: HTTP 202; created lead 7 with `status=pending` and no false phone match.
  - Invalid request: HTTP 400 with both expected validation errors.

  ## Manual test requests

  Set `URL` to the test webhook URL, clear the `lead_intake_template` rows, then run these requests in order. Replace `URL` in each command with the test URL if your shell does not define it.

  1. New request, then same payload and idempotency key. The first call returns HTTP 202 and inserts one `pending` row. Repeating it returns HTTP 200 with the same `leadId` and inserts nothing.

     ```bash
     curl -i -X POST "$URL" -H "Content-Type: application/json" -H "Idempotency-Key: test-001" -d '{"name":"Ada Lovelace","email":" Ada@Example.com ","phone":"+49 30 1234 5678","company":"Analytical Engines","message":"First enquiry","source":"test"}'
     ```

  2. Changed payload and the same idempotency key. Change only the message; the response is HTTP 409 and no row is inserted.

     ```bash
     curl -i -X POST "$URL" -H "Content-Type: application/json" -H "Idempotency-Key: test-001" -d '{"name":"Ada Lovelace","email":"ada@example.com","phone":"0049 (30) 1234-5678","company":"Analytical Engines","message":"Changed enquiry","source":"test"}'
     ```

  3. Same normalized email and a different idempotency key. The response is HTTP 202. A new row is inserted with `status=manual_review`, the first row ID in `possible_duplicate_of`, and `email,phone,name,company` in `duplicate_signals`.

     ```bash
     curl -i -X POST "$URL" -H "Content-Type: application/json" -H "Idempotency-Key: test-002" -d '{"name":"Ada Lovelace","email":"ADA@example.com","phone":"0049 30 1234 5678","company":"Analytical Engines","message":"Second enquiry","source":"test"}'
     ```

  4. Same normalized phone with a different email and idempotency key. The response is HTTP 202. The new row uses `manual_review`; `duplicate_signals` contains `phone` plus matching supporting fields.

     ```bash
     curl -i -X POST "$URL" -H "Content-Type: application/json" -H "Idempotency-Key: test-003" -d '{"name":"Ada Lovelace","email":"ada@other.example","phone":"+49 (30) 1234-5678","company":"Analytical Engines","message":"Alternate email","source":"test"}'
     ```

  5. Different person with no matching contact details. The response is HTTP 202 and the new row remains `pending` with empty duplicate fields.

     ```bash
     curl -i -X POST "$URL" -H "Content-Type: application/json" -H "Idempotency-Key: test-004" -d '{"name":"Grace Hopper","email":"grace@example.net","phone":"+1 202 555 0147","company":"Compiler Co","message":"New enquiry","source":"test"}'
     ```

  6. Missing optional phone. The response is HTTP 202 and an empty phone does not match another empty phone. This row remains `pending` because its email is new.

     ```bash
     curl -i -X POST "$URL" -H "Content-Type: application/json" -H "Idempotency-Key: test-005" -d '{"name":"Katherine Johnson","email":"katherine@example.org","company":"Orbital Co","message":"No phone supplied","source":"test"}'
     ```

  Re-run an invalid request, such as an empty object with no idempotency header, and confirm HTTP 400 before activation.

  ## Production limitations

  Person-level duplicate detection is probabilistic. Email or phone matches trigger review; name and company are recorded only as supporting signals and never establish identity by themselves.

  The lookups and insertion are separate operations. Under concurrent requests, n8n Data Tables do not provide database-level uniqueness or atomic identity controls.

  Use this version for demonstrations, prototypes, and low-concurrency intake. High-concurrency or business-critical systems should enforce idempotency and duplicate-review controls at the database level, such as in the PostgreSQL version.

  Before production use, also add:

  - Webhook authentication
  - Rate limiting
  - Downstream delivery processing
  - Bounded retries
  - Failure monitoring
  - Manual review for terminal failures
  - Data retention and deletion rules
