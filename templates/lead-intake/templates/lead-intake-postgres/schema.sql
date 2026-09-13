CREATE SCHEMA IF NOT EXISTS n8n_templates;

  CREATE TABLE IF NOT EXISTS n8n_templates.lead_intake (
      id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      idempotency_key text NOT NULL UNIQUE,
      payload_hash text NOT NULL,
      name text NOT NULL DEFAULT '',
      email text NOT NULL,
      company text NOT NULL DEFAULT '',
      message text NOT NULL DEFAULT '',
      source text NOT NULL DEFAULT 'website',
      status text NOT NULL DEFAULT 'pending'
          CHECK (status IN ('pending', 'processing', 'completed', 'retry', 'review')),
      attempt_count integer NOT NULL DEFAULT 0
          CHECK (attempt_count >= 0),
      next_attempt_at timestamptz,
      lease_token text,
      leased_until timestamptz,
      last_error text,
      received_at timestamptz NOT NULL DEFAULT now(),
      processed_at timestamptz,
      updated_at timestamptz NOT NULL DEFAULT now()
  );

  CREATE INDEX IF NOT EXISTS lead_intake_delivery_queue_idx
      ON n8n_templates.lead_intake (status, next_attempt_at, received_at);

  CREATE OR REPLACE FUNCTION n8n_templates.enqueue_lead(
      p_idempotency_key text,
      p_payload_hash text,
      p_name text,
      p_email text,
      p_company text,
      p_message text,
      p_source text
  )
  RETURNS TABLE (
      lead_id bigint,
      created boolean
  )
  LANGUAGE plpgsql
  AS $$
  DECLARE
      existing_id bigint;
      existing_hash text;
  BEGIN
      IF nullif(trim(p_idempotency_key), '') IS NULL THEN
          RAISE EXCEPTION 'IDEMPOTENCY_KEY_REQUIRED';
      END IF;

      IF nullif(trim(p_payload_hash), '') IS NULL THEN
          RAISE EXCEPTION 'PAYLOAD_HASH_REQUIRED';
      END IF;

      INSERT INTO n8n_templates.lead_intake (
          idempotency_key,
          payload_hash,
          name,
          email,
          company,
          message,
          source
      )
      VALUES (
          trim(p_idempotency_key),
          trim(p_payload_hash),
          coalesce(trim(p_name), ''),
          lower(trim(p_email)),
          coalesce(trim(p_company), ''),
          coalesce(trim(p_message), ''),
          coalesce(nullif(trim(p_source), ''), 'website')
      )
      ON CONFLICT (idempotency_key) DO NOTHING
      RETURNING id INTO existing_id;

      IF existing_id IS NOT NULL THEN
          lead_id := existing_id;
          created := true;
          RETURN NEXT;
          RETURN;
      END IF;

      SELECT id, payload_hash
      INTO existing_id, existing_hash
      FROM n8n_templates.lead_intake
      WHERE idempotency_key = trim(p_idempotency_key);

      IF existing_hash <> trim(p_payload_hash) THEN
          RAISE EXCEPTION 'IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD';
      END IF;

      lead_id := existing_id;
      created := false;
      RETURN NEXT;
  END;
  $$;

  COMMENT ON TABLE n8n_templates.lead_intake IS
      'Durable lead intake and delivery queue for the Morsof n8n template.';

  COMMENT ON COLUMN n8n_templates.lead_intake.idempotency_key IS
      'Stable caller-supplied key used to prevent duplicate lead creation.';

  COMMENT ON COLUMN n8n_templates.lead_intake.payload_hash IS
      'Hash of normalized lead fields used to detect conflicting replays.';
