# Invoice Payment Follow-up Preparation

A credential-free n8n workflow that validates invoice records, classifies payment state, prepares reminder drafts for human review, and records each prepared stage without contacting customers.

## Intended users

- SME finance and accounts-receivable teams
- Operations teams that review payment follow-ups
- n8n users connecting finance, CRM, ERP, email, or WhatsApp systems
- Consultants building a controlled reminder process

## What it does

1. Starts manually and loads three fictional invoice records.
2. Creates or reuses the `invoice_reminder_history` Data Table.
3. Normalizes invoice, customer, contact, currency, amount, status, and date fields.
4. Classifies each record as `upcoming`, `due`, `overdue`, `paid`, `partially_paid`, `disputed`, `invalid`, or `requiring_manual_review`.
5. Assigns a configurable reminder stage to eligible records.
6. Marks repeated invoice-stage pairs within one execution as already prepared.
7. Checks the invoice ID and reminder stage against prior preparations.
8. Stores a new audit row only when that exact stage has not been prepared.
9. Returns one of five explicit output paths: `ready_for_review`, `no_action_required`, `manual_review`, `invalid_record`, or `already_prepared`.

The workflow has no delivery node. It does not send email, WhatsApp messages, or other external communications.

## Setup

1. Download `invoice-payment-follow-up.json`.
2. Import it into n8n and keep it inactive.
3. Confirm that your n8n version includes the built-in Data Table node.
4. Open **Validate Normalize and Classify** and review the configuration constants.
5. Run the manual test plan below with fictional records.
6. Replace **Load Fictional Invoice Samples** with your own input only after its fields match the input contract.

The first execution creates `invoice_reminder_history`. No credentials or paid services are required.

## Configuration

The first lines of **Validate Normalize and Classify** contain the supported settings:

| Setting | Default | Purpose |
| --- | --- | --- |
| `UPCOMING_DAYS_BEFORE_DUE` | `3` | Prepare the upcoming reminder when the due date is this many days away or closer. |
| `OVERDUE_STAGES` | 3, 7, and 14 days | Select the latest eligible overdue stage. Keep entries ordered from earliest to latest. |
| `EVALUATION_DATE` | blank | Use the current UTC date. Set a fictional `YYYY-MM-DD` date for repeatable tests. |
| `AMOUNT_TOLERANCE` | `0.01` | Allowed difference when checking `totalAmount - paidAmount = outstandingAmount`. |

All date-only comparisons use UTC. Adapt the date logic before production if the accounting process uses another business time zone.

## Data Table schema

The workflow creates `invoice_reminder_history` with these columns:

| Column | Type | Purpose |
| --- | --- | --- |
| `invoice_id` | string | Stable source invoice or receivable ID. |
| `reminder_stage` | string | Prepared stage, such as `due_today` or `overdue_7_days`. |
| `classification` | string | Payment timing classification at preparation time. |
| `customer_id` | string | Stable source customer ID. |
| `recipient_email` | string | Normalized recipient email, if supplied. |
| `recipient_phone` | string | Normalized phone digits with a leading `+`, if supplied. |
| `currency` | string | Three-letter currency code. |
| `outstanding_amount` | number | Amount outstanding at preparation time. |
| `due_date` | date | Invoice due date. |
| `review_status` | string | Starts as `pending_manual_approval`. |
| `draft_subject` | string | Proposed subject for later review and delivery. |
| `prepared_at` | date | UTC timestamp when the draft was prepared. |
| `source_updated_at` | date | Timestamp supplied by the source record. |

Rows are append-only by reminder stage. The workflow performs an exact lookup using `invoice_id` and `reminder_stage`; it does not scan the full table in Code nodes.

## Input contract

Each item must have this shape:

```json
{
  "invoiceId": "INV-FICTION-2001",
  "customer": {
    "id": "CUST-FICTION-20",
    "name": "Harbor Sample GmbH",
    "email": "accounts@harbor-sample.example",
    "phone": ""
  },
  "currency": "EUR",
  "totalAmount": 900,
  "paidAmount": 0,
  "outstandingAmount": 900,
  "dueDate": "2030-06-20",
  "paymentStatus": "unpaid",
  "disputed": false,
  "updatedAt": "2030-06-17T09:00:00.000Z"
}
```

Required fields are `invoiceId`, `customer.id`, `customer.name`, `currency`, all three amount fields, `dueDate`, `paymentStatus`, and `disputed`. At least one of `customer.email` or `customer.phone` is required before a draft can be prepared. `paymentStatus` accepts `unpaid`, `paid`, or `partially_paid`.

Use a stable invoice ID. Reusing an ID for a different source invoice can suppress a reminder stage.

## Output contract

Every output retains the normalized fields and adds:

| Field | Meaning |
| --- | --- |
| `classification` | Normalized business state. |
| `reminderStage` | Eligible stage, or an empty string when no draft is prepared. |
| `outputPath` | One of the five explicit workflow results. |
| `actionReason` | Machine-readable reason for the result. |
| `draft` | Channel-ready draft object, or `null`. |
| `historyRecordId` | Data Table row ID for new or existing preparations when available. |
| `reviewStatus` | `pending_manual_approval` or `already_prepared` on reminder paths. |

Ready for review:

```json
{
  "invoiceId": "INV-FICTION-2001",
  "classification": "upcoming",
  "reminderStage": "upcoming_3_days",
  "outputPath": "ready_for_review",
  "actionReason": "reminder_stage_eligible",
  "reviewStatus": "pending_manual_approval",
  "deliveryEnabled": false,
  "draft": {
    "reminderStage": "upcoming_3_days",
    "recipient": {
      "customerId": "CUST-FICTION-20",
      "customerName": "Harbor Sample GmbH",
      "email": "accounts@harbor-sample.example",
      "phone": ""
    },
    "subject": "Payment reminder review: invoice INV-FICTION-2001",
    "title": "Review upcoming_3_days for INV-FICTION-2001",
    "messageVariables": {
      "invoiceId": "INV-FICTION-2001",
      "customerName": "Harbor Sample GmbH",
      "currency": "EUR",
      "totalAmount": 900,
      "paidAmount": 0,
      "outstandingAmount": 900,
      "dueDate": "2030-06-20"
    }
  }
}
```

Manual review:

```json
{
  "invoiceId": "INV-FICTION-2002",
  "classification": "partially_paid",
  "reminderStage": "",
  "outputPath": "manual_review",
  "actionReason": "partial_payment",
  "draft": null
}
```

Already prepared:

```json
{
  "invoiceId": "INV-FICTION-2001",
  "classification": "upcoming",
  "reminderStage": "upcoming_3_days",
  "outputPath": "already_prepared",
  "reviewStatus": "already_prepared",
  "historyRecordId": 1
}
```

## Reminder-stage logic

| Condition | Classification | Stage or result |
| --- | --- | --- |
| More than 3 days before due date | `upcoming` | `no_action_required` |
| 1 to 3 days before due date | `upcoming` | `upcoming_3_days` |
| Due today | `due` | `due_today` |
| 1 to 2 days overdue | `overdue` | `no_action_required` |
| 3 to 6 days overdue | `overdue` | `overdue_3_days` |
| 7 to 13 days overdue | `overdue` | `overdue_7_days` |
| 14 or more days overdue | `overdue` | `overdue_14_days` |
| Fully paid with zero outstanding | `paid` | `no_action_required` |

The latest eligible stage is selected. Preparing `overdue_3_days` does not block a later `overdue_7_days` preparation. Replaying the same invoice at the same stage returns `already_prepared`.

## Manual review conditions

The workflow prepares no draft when any of these conditions is present:

- No email and no phone
- A disputed invoice
- A partial payment or `partially_paid` status
- `totalAmount - paidAmount` does not match `outstandingAmount` within the configured tolerance
- `paid` status with a positive outstanding amount
- `unpaid` status with a paid amount or no outstanding balance

Missing core identifiers, an invalid currency or amount, an invalid due date, or an unsupported payment status follows `invalid_record` instead.

## Failure handling

Data Table creation, lookup, and insertion retry at most three times with a one-second wait. If all attempts fail, n8n stops the execution and records the failed node. The history row is written only after validation, classification, and the exact-stage lookup succeed.

The workflow has no loop, schedule, webhook, or outbound request. Each manual execution processes only the finite array returned by **Load Fictional Invoice Samples**.

## Security and privacy

- The included names, IDs, addresses, and invoices are fictional. `.example` email domains cannot receive mail.
- The workflow contains no credentials, secrets, webhook IDs, execution data, pinned data, or instance metadata.
- Only fields needed for review, replay protection, and audit history are stored.
- Apply your own access, retention, deletion, and compliance rules to customer and financial records.
- Review n8n user permissions and Data Table access before using production data.
- Do not place secrets or payment credentials in the input or reminder history.

## Production limitations

n8n Data Tables do not provide database-level uniqueness for `invoice_id + reminder_stage`, and the lookup and insert are separate operations. Concurrent executions can both pass the lookup and create duplicate history rows. Use a transactional database with a unique constraint before using this pattern for concurrent or business-critical processing.

The template does not reconcile payments, calculate taxes or fees, interpret credit notes, resolve disputes, approve content, or verify that a contact is authorized. It has not been tested against a specific ERP, CRM, email provider, or WhatsApp service.

## Exact manual test plan

Keep the workflow inactive. For repeatable dates, set `EVALUATION_DATE` in **Validate Normalize and Classify** to `2030-06-20`. Replace the `invoices` array in **Load Fictional Invoice Samples** for each test. Use unique IDs except where a replay is required. Clear `invoice_reminder_history` before test 1.

1. **Upcoming unpaid invoice:** Use due date `2030-06-22`, status `unpaid`, total `100`, paid `0`, outstanding `100`, and a valid email. Expected: `classification=upcoming`, `reminderStage=upcoming_3_days`, `outputPath=ready_for_review`, and one history row.
2. **Invoice due today:** Use due date `2030-06-20` with the other valid unpaid fields from test 1. Expected: `classification=due`, `reminderStage=due_today`, `outputPath=ready_for_review`, and one history row.
3. **First overdue reminder:** Use due date `2030-06-17`. Expected: `classification=overdue`, `reminderStage=overdue_3_days`, `outputPath=ready_for_review`, and one history row.
4. **Later overdue stage:** Use due date `2030-06-12`. Expected: `classification=overdue`, `reminderStage=overdue_7_days`, `outputPath=ready_for_review`, and one history row. If the same invoice already has `overdue_3_days`, both stage rows remain.
5. **Exact stage already prepared:** Run test 4 again with the same invoice ID. Expected: `outputPath=already_prepared`, the existing `historyRecordId`, and no additional row.
6. **Fully paid invoice:** Use status `paid`, total `100`, paid `100`, and outstanding `0`. Expected: `classification=paid`, `outputPath=no_action_required`, and no history row.
7. **Partially paid invoice:** Use status `partially_paid`, total `100`, paid `40`, and outstanding `60`. Expected: `classification=partially_paid`, `outputPath=manual_review`, `actionReason` containing `partial_payment`, and no history row.
8. **Disputed invoice:** Set `disputed=true` on an otherwise valid unpaid invoice. Expected: `classification=disputed`, `outputPath=manual_review`, `actionReason` containing `invoice_disputed`, and no history row.
9. **Missing contact details:** Set both email and phone to empty strings. Expected: `classification=requiring_manual_review`, `outputPath=manual_review`, `actionReason` containing `customer_contact_missing`, and no history row.
10. **Invalid due date:** Use `2030-02-30`. Expected: `classification=invalid`, `outputPath=invalid_record`, `actionReason` containing `due_date_invalid`, and no history row.
11. **Inconsistent amounts:** Use total `100`, paid `20`, and outstanding `90`. Expected: `classification=partially_paid`, `outputPath=manual_review`, `actionReason` containing `amounts_inconsistent`, and no history row.
12. **Duplicate or replayed input:** Put the same eligible record into the input array twice, then run the resulting record again in a second execution without changing its invoice ID, due date, or stage. Expected: the first item is `ready_for_review`; the repeated item and later replay are `already_prepared`; one history row exists for that invoice and stage.
13. **Multiple invoices in one execution:** Load three records in the same array: one valid upcoming invoice, one paid invoice, and one disputed invoice, each with a unique ID. Expected: one `ready_for_review`, one `no_action_required`, and one `manual_review` result. Only the upcoming invoice creates a history row, and every output retains its own invoice and customer fields.

After each test, inspect the final node output and the Data Table row count. Do not add or enable a delivery node during these tests.

## Connecting a delivery channel later

Keep **Ready for Review** as the preparation boundary. Add a separate human approval step after it, then connect the approved branch to an email, CRM, ERP, or WhatsApp node. Map only fields from `draft.recipient`, `draft.subject`, `draft.title`, and `draft.messageVariables`.

Configure credentials in n8n rather than in the workflow JSON. Add provider-specific retry limits, rate limits, delivery-status recording, and failure alerts. Test with non-production recipients before activation. Do not connect delivery to **Already Prepared**, **Manual Review**, **Invalid Record**, or **No Action Required**.
