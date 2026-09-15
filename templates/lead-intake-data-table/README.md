# Lead Intake with n8n Data Tables

A credential-free lead-intake workflow with validation, expiring request-idempotency keys, possible duplicate review, conflict handling, and durable lead storage.

## What it does

1. Receives lead data through an HTTP POST webhook.
2. Requires an `Idempotency-Key` header.
3. Validates the request and normalizes email and optional phone fields.
4. Hashes only the normalized business payload.
5. Stores leads in `lead_intake_template` and request keys in `lead_intake_idempotency`.
6. Treats a key as active for 24 hours by default.
7. Returns the original lead for an active key with the same payload, or HTTP 409 if its payload changed.
8. Treats an expired key as new and still runs possible duplicate review.
9. Removes at most 100 expired key records each hour without deleting or changing leads.

Request idempotency protects retries for a limited time. Lead retention controls how long submitted lead data remains available. Expiring or deleting a key record has no effect on its lead row.

## Import and configuration

1. Download `lead-intake-data-table.json`.
2. Import it into n8n and leave it inactive.
3. In **Validate and Normalize**, change `IDEMPOTENCY_TTL_HOURS` if the default 24-hour lifetime is not suitable.
4. Adjust the 100-row limit in **Find Expired Keys** or the hourly **Cleanup Schedule** only if needed.
5. Complete the migration below for an existing v0.3 import.
6. Test every path before activation.

Fresh imports create these tables on first use:

### `lead_intake_template`

| Column | Type |
| --- | --- |
| `name` | string |
| `email` | string |
| `phone` | string |
| `company` | string |
| `message` | string |
| `source` | string |
| `status` | string |
| `possible_duplicate_of` | string |
| `duplicate_signals` | string |
| `attempt_count` | number |
| `last_error` | string |
| `received_at` | date |
| `processed_at` | date |

### `lead_intake_idempotency`

| Column | Type |
| --- | --- |
| `idempotency_key` | string |
| `payload_hash` | string |
| `lead_id` | number |
| `created_at` | date |
| `expires_at` | date |

## Migrating an existing v0.3 import

Keep `lead_intake_template` and all its rows. The workflow no longer reads or writes its legacy `idempotency_key` and `payload_hash` columns, but they can remain in place.

Create `lead_intake_idempotency` with the five columns above before accepting requests. To preserve the remaining replay window for existing v0.3 rows, copy each still-active key into the new table:

- `idempotency_key` from the lead row
- `payload_hash` from the lead row
- `lead_id` from the lead row `id`
- `created_at` from `received_at`
- `expires_at` equal to `received_at` plus the configured lifetime

Skip rows whose calculated expiry is already past. If no old keys are copied, existing leads remain intact, but their old keys are treated as expired immediately.

## Example request

```bash
curl -i -X POST \
  "$URL" \
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

Email comparison is case-insensitive after trimming whitespace. Phone comparison removes non-digits and treats an international `00` prefix like `+`; it does not infer a country code. Timestamps and request metadata remain outside the payload hash.

## Responses

New lead, HTTP 202:

```json
{"accepted":true,"duplicate":false,"leadId":1}
```

Active-key replay, HTTP 200:

```json
{"accepted":true,"duplicate":true,"leadId":1}
```

Active-key conflict, HTTP 409:

```json
{"accepted":false,"error":"IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD"}
```

Invalid request, HTTP 400:

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

- A new request using `v04-expiry-001` returned HTTP 202 and created lead 8 with `status=pending`.
- Replaying the active key with the same payload returned HTTP 200 and lead 8.
- Reusing the active key with a changed payload returned HTTP 409.
- Matching normalized contact details with `v04-expiry-002` returned HTTP 202 and created lead 9 with `status=manual_review`, `possible_duplicate_of=8`, and `duplicate_signals=email,phone,name,company`.
- A different contact without a phone using `v04-expiry-003` returned HTTP 202 and created lead 10 with `status=pending` and empty duplicate fields.
- An invalid request returned HTTP 400 with both expected validation errors.
- The default `expires_at` value was 24 hours after `created_at`.
- After the original `v04-expiry-001` key was set to expire in the past, reusing its original payload returned HTTP 202 and created lead 11. Lead 11 had `status=manual_review`, `possible_duplicate_of=8`, and `duplicate_signals=email,phone,name,company`.
- The workflow created a new active `v04-expiry-001` key record linked to lead 11.
- `Find Expired Keys` selected only the expired key linked to lead 8. `Delete Expired Key` removed it while the active key linked to lead 11 remained.
- Leads 8 and 11 remained unchanged after key cleanup.

## Manual n8n test sequence

Keep the workflow inactive. Clear both test tables, click **Execute workflow**, copy the test webhook URL from **Receive Lead**, and set it as `URL` in your shell.

1. Submit a new request. Confirm HTTP 202, one `pending` lead row, and one key row whose `lead_id` points to it.

   ```bash
   curl -i -X POST "$URL" -H "Content-Type: application/json" -H "Idempotency-Key: expiry-001" -d '{"name":"Ada Lovelace","email":" Ada@Example.com ","phone":"+49 30 1234 5678","company":"Analytical Engines","message":"First enquiry","source":"test"}'
   ```

2. Repeat the same command before the key expires. Confirm HTTP 200 with the original lead ID and no new row in either table.

3. Reuse the active key with a changed message. Confirm HTTP 409 and no new row.

   ```bash
   curl -i -X POST "$URL" -H "Content-Type: application/json" -H "Idempotency-Key: expiry-001" -d '{"name":"Ada Lovelace","email":"ada@example.com","phone":"0049 (30) 1234-5678","company":"Analytical Engines","message":"Changed enquiry","source":"test"}'
   ```

4. Use a new key with the same normalized email and phone. Confirm HTTP 202 and a separate lead with `status=manual_review`, the first lead ID in `possible_duplicate_of`, and `email,phone,name,company` in `duplicate_signals`.

   ```bash
   curl -i -X POST "$URL" -H "Content-Type: application/json" -H "Idempotency-Key: expiry-002" -d '{"name":"Ada Lovelace","email":"ADA@example.com","phone":"0049 30 1234 5678","company":"Analytical Engines","message":"Second enquiry","source":"test"}'
   ```

5. Submit a different person without a phone. Confirm HTTP 202, `status=pending`, and no false phone match.

   ```bash
   curl -i -X POST "$URL" -H "Content-Type: application/json" -H "Idempotency-Key: expiry-003" -d '{"name":"Katherine Johnson","email":"katherine@example.org","company":"Orbital Co","message":"No phone supplied","source":"test"}'
   ```

6. In `lead_intake_idempotency`, change the `expires_at` value for `expiry-001` to a timestamp in the past. Repeat the request from step 1. Confirm HTTP 202 with a new lead ID. Because the contact details still match, the new lead must use `manual_review`; the expired key no longer controls replay detection.

7. Record the lead IDs, run the cleanup path from **Cleanup Schedule**, and confirm the expired key row is deleted while every lead row and value remains unchanged. The cleanup reads at most 100 expired rows per run.

8. Send an empty request without an idempotency header. Confirm HTTP 400 with both validation errors.

   ```bash
   curl -i -X POST "$URL" -H "Content-Type: application/json" -d '{}'
   ```

## Production limitations

Person-level duplicate detection is probabilistic. Email or phone matches trigger review; name and company are supporting signals and never establish identity by themselves.

Data Table lookups, lead insertion, key insertion, and cleanup are separate operations. Concurrent requests can race because n8n Data Tables do not provide database-level uniqueness or atomic transactions across these operations.

Use this version for demonstrations, prototypes, and low-concurrency intake. High-concurrency or business-critical systems should enforce idempotency, expiry, and duplicate-review controls in a transactional database.

Before production use, also add webhook authentication, rate limiting, bounded retries, failure monitoring, and explicit lead-retention rules.
