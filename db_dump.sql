--
-- PostgreSQL database dump
--

\restrict ZMAAuTc60b5WXmES8hflR4KkNU90w5kw74AJheKP3VBourH4padeZ3EV0gCZMJv

-- Dumped from database version 17.11 (Debian 17.11-1.pgdg13+2)
-- Dumped by pg_dump version 18.1

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: contact_set_updatedAt(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public."contact_set_updatedAt"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

BEGIN

    NEW."updatedAt" := now();

    RETURN NEW;

END;

$$;


ALTER FUNCTION public."contact_set_updatedAt"() OWNER TO postgres;

--
-- Name: investment_account_balance(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.investment_account_balance() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
DECLARE parent_key text := substr(TG_TABLE_NAME,11)||'_id'; invalid boolean;
BEGIN
  -- A product change cannot leave incompatible options attached.
  EXECUTE format('SELECT EXISTS(SELECT 1 FROM fact_find_investment_holding h JOIN investment_option o ON o.investment_option_id=h.investment_option_id LEFT JOIN financial_product p ON p.id=$2 WHERE h.%I=$1 AND (p.rex_id IS NULL OR o.linked_product IS DISTINCT FROM p.rex_id))', parent_key)
    INTO invalid USING NEW.id, NEW.financial_product_id;
  IF invalid THEN RAISE EXCEPTION 'Holdings must belong to the selected financial product' USING ERRCODE='23514'; END IF;
  IF NOT NEW.holdings_configured THEN
    NEW.account_balance := NULL;
  ELSE
    EXECUTE format('SELECT CASE WHEN count(*) FILTER(WHERE o.current_price IS NULL)>0 THEN NULL ELSE round(coalesce(sum(h.quantity*o.current_price),0),2) END FROM fact_find_investment_holding h JOIN investment_option o ON o.investment_option_id=h.investment_option_id WHERE h.%I=$1', parent_key)
      INTO NEW.account_balance USING NEW.id;
  END IF;
  RETURN NEW;
END $_$;


ALTER FUNCTION public.investment_account_balance() OWNER TO postgres;

--
-- Name: investment_holding_revalue(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.investment_holding_revalue() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE h fact_find_investment_holding;
BEGIN
  IF TG_OP='DELETE' THEN h:=OLD; ELSE h:=NEW; END IF;
  IF h.investment_platform_id IS NOT NULL THEN UPDATE fact_find_investment_platform SET holdings_configured=true WHERE id=h.investment_platform_id;
  ELSIF h.retirement_asset_id IS NOT NULL THEN UPDATE fact_find_retirement_asset SET holdings_configured=true WHERE id=h.retirement_asset_id;
  ELSE UPDATE fact_find_superannuation SET holdings_configured=true WHERE id=h.superannuation_id; END IF;
  RETURN NULL;
END $$;


ALTER FUNCTION public.investment_holding_revalue() OWNER TO postgres;

--
-- Name: investment_holding_validate(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.investment_holding_validate() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
DECLARE product uuid; linked integer; parent_table text; parent_key text; parent_id uuid;
BEGIN
  IF TG_OP='UPDATE' AND (NEW.investment_platform_id,NEW.retirement_asset_id,NEW.superannuation_id) IS DISTINCT FROM (OLD.investment_platform_id,OLD.retirement_asset_id,OLD.superannuation_id) THEN
    RAISE EXCEPTION 'A holding cannot be moved to another account' USING ERRCODE='23514';
  END IF;
  IF num_nonnulls(NEW.investment_platform_id,NEW.retirement_asset_id,NEW.superannuation_id)<>1 THEN
    RAISE EXCEPTION 'A holding requires exactly one account' USING ERRCODE='23514';
  END IF;
  IF NEW.investment_platform_id IS NOT NULL THEN parent_key:='investment_platform'; parent_id:=NEW.investment_platform_id;
  ELSIF NEW.retirement_asset_id IS NOT NULL THEN parent_key:='retirement_asset'; parent_id:=NEW.retirement_asset_id;
  ELSE parent_key:='superannuation'; parent_id:=NEW.superannuation_id; END IF;
  parent_table:='fact_find_'||parent_key;
  EXECUTE format('SELECT financial_product_id FROM %I WHERE id=$1 FOR UPDATE',parent_table) INTO product USING parent_id;
  SELECT o.linked_product INTO linked FROM investment_option o WHERE investment_option_id=NEW.investment_option_id FOR SHARE;
  IF product IS NULL OR linked IS NULL OR NOT EXISTS(SELECT 1 FROM financial_product p WHERE p.id=product AND p.rex_id=linked) THEN
    RAISE EXCEPTION 'Investment option does not belong to the account financial product' USING ERRCODE='23514';
  END IF;
  NEW.updated_at:=now();
  RETURN NEW;
END $_$;


ALTER FUNCTION public.investment_holding_validate() OWNER TO postgres;

--
-- Name: investment_option_revalue(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.investment_option_revalue() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE fact_find_investment_platform SET holdings_configured=true WHERE id IN (SELECT investment_platform_id FROM fact_find_investment_holding WHERE investment_option_id=NEW.investment_option_id);
  UPDATE fact_find_retirement_asset SET holdings_configured=true WHERE id IN (SELECT retirement_asset_id FROM fact_find_investment_holding WHERE investment_option_id=NEW.investment_option_id);
  UPDATE fact_find_superannuation SET holdings_configured=true WHERE id IN (SELECT superannuation_id FROM fact_find_investment_holding WHERE investment_option_id=NEW.investment_option_id);
  RETURN NULL;
END $$;


ALTER FUNCTION public.investment_option_revalue() OWNER TO postgres;

--
-- Name: investment_product_revalidate(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.investment_product_revalidate() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE fact_find_investment_platform SET financial_product_id=NEW.id WHERE financial_product_id=NEW.id;
  UPDATE fact_find_retirement_asset SET financial_product_id=NEW.id WHERE financial_product_id=NEW.id;
  UPDATE fact_find_superannuation SET financial_product_id=NEW.id WHERE financial_product_id=NEW.id;
  RETURN NULL;
END $$;


ALTER FUNCTION public.investment_product_revalidate() OWNER TO postgres;

--
-- Name: protect_contact_entity_type(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.protect_contact_entity_type() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.entity_type <> 'individual' AND EXISTS(SELECT 1 FROM contact WHERE entity_id=NEW.id) THEN
    RAISE EXCEPTION 'Contact-linked entities must be Individual' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;


ALTER FUNCTION public.protect_contact_entity_type() OWNER TO postgres;

--
-- Name: sync_contact_entity(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sync_contact_entity() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
 IF TG_OP='UPDATE' AND NEW.entity_id IS DISTINCT FROM OLD.entity_id THEN
  RAISE EXCEPTION 'A contact entity cannot be reassigned' USING ERRCODE='23514';
 END IF;
 IF TG_OP='INSERT' AND (NEW.entity_id IS NULL OR NEW.entity_id='00000000-0000-0000-0000-000000000000') THEN
  NEW.entity_id:=NEW.id;
  INSERT INTO entity(id,entity_type,display_name,financial_planner_id) VALUES(NEW.entity_id,'individual',
   coalesce(nullif(trim(NEW."fullName"),''),nullif(trim(concat_ws(' ',NEW."firstName",NEW."lastName")),''),'Unnamed contact'),NEW."financialPlannerId");
 END IF;
 IF NOT EXISTS(SELECT 1 FROM entity WHERE id=NEW.entity_id AND entity_type='individual') THEN
  RAISE EXCEPTION 'Contacts require an Individual entity' USING ERRCODE='23514';
 END IF;
 UPDATE entity SET display_name=coalesce(nullif(trim(NEW."fullName"),''),nullif(trim(concat_ws(' ',NEW."firstName",NEW."lastName")),''),'Unnamed contact'),updated_at=now() WHERE id=NEW.entity_id;
 RETURN NEW;
END $$;


ALTER FUNCTION public.sync_contact_entity() OWNER TO postgres;

--
-- Name: advice_case_number_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.advice_case_number_seq
    START WITH 1001
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.advice_case_number_seq OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: business_unit; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.business_unit (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    code text NOT NULL,
    description text,
    abn text,
    afsl_number text,
    address text,
    email text,
    phone text,
    parent_business_unit_id uuid,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    website text,
    CONSTRAINT business_unit_check CHECK ((parent_business_unit_id IS DISTINCT FROM id)),
    CONSTRAINT business_unit_code_check CHECK ((length(TRIM(BOTH FROM code)) > 0)),
    CONSTRAINT business_unit_name_check CHECK ((length(TRIM(BOTH FROM name)) > 0))
);


ALTER TABLE public.business_unit OWNER TO postgres;

--
-- Name: case_entity; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.case_entity (
    case_id uuid NOT NULL,
    entity_id uuid NOT NULL,
    role text DEFAULT 'client'::text NOT NULL,
    details_snapshot jsonb NOT NULL
);


ALTER TABLE public.case_entity OWNER TO postgres;

--
-- Name: case_financial_planner; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.case_financial_planner (
    case_id uuid NOT NULL,
    financial_planner_id uuid NOT NULL,
    is_primary boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.case_financial_planner OWNER TO postgres;

--
-- Name: contact; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.contact (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    "createdAt" timestamp(6) with time zone DEFAULT now() NOT NULL,
    "updatedAt" timestamp(6) with time zone DEFAULT now() NOT NULL,
    "firstName" text,
    "middleName" text,
    "lastName" text,
    "fullName" text,
    salutation text,
    "birthDate" date,
    email1 character varying(255),
    email2 character varying(255),
    "mobilePhone" character varying(50),
    "phoneHome" character varying(50),
    "phoneWork" character varying(50),
    gender text,
    "maritalStatus" text,
    "addressLine1" text,
    "addressLine2" text,
    suburb text,
    state text,
    "postCode" text,
    country text,
    "postalSameAsResidential" boolean DEFAULT true NOT NULL,
    "taxResidentFlag" boolean,
    "taxFileNumber" character varying(9),
    "businessUnitId" uuid,
    "financialPlannerId" uuid,
    entity_id uuid NOT NULL
);


ALTER TABLE public.contact OWNER TO postgres;

--
-- Name: crm_case; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.crm_case (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    status text DEFAULT 'open'::text NOT NULL,
    captured_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    case_number bigint DEFAULT nextval('public.advice_case_number_seq'::regclass) NOT NULL,
    advice_type text DEFAULT 'Initial'::text NOT NULL,
    financial_planner text,
    CONSTRAINT case_planner_nonempty CHECK (((financial_planner IS NULL) OR (length(TRIM(BOTH FROM financial_planner)) > 0))),
    CONSTRAINT crm_case_advice_type_check CHECK ((advice_type = ANY (ARRAY['Initial'::text, 'Review'::text, 'Foundational'::text]))),
    CONSTRAINT crm_case_name_check CHECK ((length(TRIM(BOTH FROM name)) > 0)),
    CONSTRAINT crm_case_status_check CHECK ((status = ANY (ARRAY['open'::text, 'closed'::text])))
);


ALTER TABLE public.crm_case OWNER TO postgres;

--
-- Name: crm_migration; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.crm_migration (
    name text NOT NULL,
    applied_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.crm_migration OWNER TO postgres;

--
-- Name: crm_note; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.crm_note (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    entity_id uuid,
    case_id uuid,
    title text NOT NULL,
    body text DEFAULT ''::text NOT NULL,
    created_by_user_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT crm_note_check CHECK (((entity_id IS NOT NULL) <> (case_id IS NOT NULL))),
    CONSTRAINT crm_note_title_check CHECK ((length(TRIM(BOTH FROM title)) > 0))
);


ALTER TABLE public.crm_note OWNER TO postgres;

--
-- Name: crm_task; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.crm_task (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    entity_id uuid,
    case_id uuid,
    title text NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    due_date date,
    completed_at timestamp with time zone,
    assigned_to_user_id uuid,
    created_by_user_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT crm_task_check CHECK (((entity_id IS NOT NULL) <> (case_id IS NOT NULL))),
    CONSTRAINT crm_task_title_check CHECK ((length(TRIM(BOTH FROM title)) > 0))
);


ALTER TABLE public.crm_task OWNER TO postgres;

--
-- Name: entity; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.entity (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    entity_type text NOT NULL,
    display_name text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    financial_planner_id uuid,
    CONSTRAINT entity_display_name_check CHECK ((length(TRIM(BOTH FROM display_name)) > 0)),
    CONSTRAINT entity_entity_type_check CHECK ((entity_type = ANY (ARRAY['individual'::text, 'joint'::text, 'company'::text, 'smsf_corporate_trustee'::text, 'smsf_individual_trustee'::text, 'family_trust'::text, 'other_trust'::text])))
);


ALTER TABLE public.entity OWNER TO postgres;

--
-- Name: entity_relationship; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.entity_relationship (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    from_entity_id uuid NOT NULL,
    to_entity_id uuid NOT NULL,
    relationship_type text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT entity_relationship_check CHECK ((from_entity_id <> to_entity_id)),
    CONSTRAINT entity_relationship_relationship_type_check CHECK ((length(TRIM(BOTH FROM relationship_type)) > 0))
);


ALTER TABLE public.entity_relationship OWNER TO postgres;

--
-- Name: fact_find_beneficiary; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_beneficiary (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    contact_id uuid,
    insurance_policy_id uuid,
    superannuation_id uuid,
    retirement_asset_id uuid,
    name text,
    beneficiary_type text,
    percentage numeric(5,2)
);


ALTER TABLE public.fact_find_beneficiary OWNER TO postgres;

--
-- Name: fact_find_business_income; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_business_income (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    business_name text,
    income_amount numeric(18,2),
    income_change_flag boolean,
    income_change_amount numeric(18,2),
    income_change_reason text,
    case_id uuid
);


ALTER TABLE public.fact_find_business_income OWNER TO postgres;

--
-- Name: fact_find_business_income_ownership; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_business_income_ownership (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    business_income_id uuid NOT NULL,
    entity_id uuid NOT NULL,
    ownership_percentage numeric(5,2),
    created_at timestamp(6) with time zone DEFAULT now() NOT NULL,
    updated_at timestamp(6) with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.fact_find_business_income_ownership OWNER TO postgres;

--
-- Name: fact_find_cash; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_cash (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    provider text,
    product_name text,
    account_number text,
    account_type text,
    account_opened date,
    balance numeric(18,2),
    interest_rate numeric(9,4),
    account_fee numeric(18,2),
    purpose text,
    savings_flag boolean,
    regular_savings_amount numeric(18,2),
    withdrawal_flag boolean,
    regular_withdrawal_amount numeric(18,2),
    tax_file_number_supplied boolean,
    client_notes text,
    financial_planner_notes text,
    case_id uuid,
    financial_product_id uuid
);


ALTER TABLE public.fact_find_cash OWNER TO postgres;

--
-- Name: fact_find_cash_ownership; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_cash_ownership (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    cash_id uuid NOT NULL,
    entity_id uuid NOT NULL,
    ownership_percentage numeric(5,2)
);


ALTER TABLE public.fact_find_cash_ownership OWNER TO postgres;

--
-- Name: fact_find_centrelink_income; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_centrelink_income (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    income_amount numeric(18,2),
    income_change_flag boolean,
    income_change_amount numeric(18,2),
    income_change_reason text,
    case_id uuid
);


ALTER TABLE public.fact_find_centrelink_income OWNER TO postgres;

--
-- Name: fact_find_centrelink_income_ownership; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_centrelink_income_ownership (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    centrelink_income_id uuid NOT NULL,
    entity_id uuid NOT NULL,
    ownership_percentage numeric(5,2),
    created_at timestamp(6) with time zone DEFAULT now() NOT NULL,
    updated_at timestamp(6) with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.fact_find_centrelink_income_ownership OWNER TO postgres;

--
-- Name: fact_find_credit_card; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_credit_card (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    provider text,
    product_name text,
    card_type text,
    establishment_date date,
    credit_limit numeric(18,2),
    current_balance numeric(18,2),
    current_interest_rate numeric(9,4),
    interest_free_period text,
    minimum_monthly_repayment numeric(18,2),
    current_monthly_repayment numeric(18,2),
    annual_account_fee numeric(18,2),
    monthly_fee numeric(18,2),
    balance_transfer_fee_amount numeric(18,2),
    balance_transfer_fee_percent numeric(9,4),
    client_notes text,
    financial_planner_notes text,
    case_id uuid,
    financial_product_id uuid
);


ALTER TABLE public.fact_find_credit_card OWNER TO postgres;

--
-- Name: fact_find_credit_card_ownership; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_credit_card_ownership (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    credit_card_id uuid NOT NULL,
    entity_id uuid NOT NULL,
    ownership_percentage numeric(5,2)
);


ALTER TABLE public.fact_find_credit_card_ownership OWNER TO postgres;

--
-- Name: fact_find_direct_investment; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_direct_investment (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    provider_name text,
    product_name text,
    account_number text,
    account_established_date date,
    investment_purchase_date date,
    purchase_price numeric(18,2),
    quantity_purchased numeric(18,6),
    opening_balance numeric(18,2),
    account_balance numeric(18,2),
    current_value numeric(18,2),
    administration_fee_amount numeric(18,2),
    administration_fee_percent numeric(9,4),
    adviser_fee_amount numeric(18,2),
    adviser_fee_percent numeric(9,4),
    management_fee_percent numeric(9,4),
    asset_fee_amount numeric(18,2),
    asset_fee_percent numeric(9,4),
    contribution_fee_amount numeric(18,2),
    contribution_fee_percent numeric(9,4),
    exit_withdrawal_fee_amount numeric(18,2),
    exit_withdrawal_fee_percent numeric(9,4),
    brokerage_buy_fee_amount numeric(18,2),
    brokerage_buy_fee_percent numeric(9,4),
    brokerage_sell_fee_amount numeric(18,2),
    brokerage_sell_fee_percent numeric(9,4),
    switch_fee_amount numeric(18,2),
    client_notes text,
    financial_planner_notes text,
    case_id uuid,
    financial_product_id uuid
);


ALTER TABLE public.fact_find_direct_investment OWNER TO postgres;

--
-- Name: fact_find_direct_investment_item; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_direct_investment_item (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    direct_investment_id uuid NOT NULL,
    name text,
    product_name text,
    quantity numeric(18,6),
    unit_price numeric(18,6),
    current_value numeric(18,2),
    allocation_percentage numeric(9,4),
    financial_product_id uuid
);


ALTER TABLE public.fact_find_direct_investment_item OWNER TO postgres;

--
-- Name: fact_find_direct_investment_ownership; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_direct_investment_ownership (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    direct_investment_id uuid NOT NULL,
    entity_id uuid NOT NULL,
    ownership_percentage numeric(5,2)
);


ALTER TABLE public.fact_find_direct_investment_ownership OWNER TO postgres;

--
-- Name: fact_find_expense; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_expense (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    category text,
    subcategory text,
    amount numeric(18,2),
    frequency text DEFAULT 'annual'::text,
    other_expense_description text,
    expected_to_change boolean,
    change_amount numeric(18,2),
    change_reason text,
    case_id uuid
);


ALTER TABLE public.fact_find_expense OWNER TO postgres;

--
-- Name: fact_find_expense_ownership; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_expense_ownership (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    expense_id uuid NOT NULL,
    entity_id uuid NOT NULL,
    ownership_percentage numeric(5,2)
);


ALTER TABLE public.fact_find_expense_ownership OWNER TO postgres;

--
-- Name: fact_find_fixed_interest; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_fixed_interest (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    provider text,
    product_name text,
    account_number text,
    investment_type text,
    start_date date,
    maturity_date date,
    balance numeric(18,2),
    interest_rate numeric(9,4),
    interest_frequency text,
    account_fee numeric(18,2),
    client_notes text,
    financial_planner_notes text,
    case_id uuid,
    financial_product_id uuid
);


ALTER TABLE public.fact_find_fixed_interest OWNER TO postgres;

--
-- Name: fact_find_fixed_interest_ownership; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_fixed_interest_ownership (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    fixed_interest_id uuid NOT NULL,
    entity_id uuid NOT NULL,
    ownership_percentage numeric(5,2)
);


ALTER TABLE public.fact_find_fixed_interest_ownership OWNER TO postgres;

--
-- Name: fact_find_foreign_income; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_foreign_income (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    income_amount numeric(18,2),
    income_change_flag boolean,
    income_change_amount numeric(18,2),
    income_change_reason text,
    case_id uuid
);


ALTER TABLE public.fact_find_foreign_income OWNER TO postgres;

--
-- Name: fact_find_foreign_income_ownership; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_foreign_income_ownership (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    foreign_income_id uuid NOT NULL,
    entity_id uuid NOT NULL,
    ownership_percentage numeric(5,2),
    created_at timestamp(6) with time zone DEFAULT now() NOT NULL,
    updated_at timestamp(6) with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.fact_find_foreign_income_ownership OWNER TO postgres;

--
-- Name: fact_find_home_contents; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_home_contents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    value numeric(18,2),
    case_id uuid
);


ALTER TABLE public.fact_find_home_contents OWNER TO postgres;

--
-- Name: fact_find_home_contents_ownership; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_home_contents_ownership (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    home_contents_id uuid NOT NULL,
    entity_id uuid NOT NULL,
    ownership_percentage numeric(5,2)
);


ALTER TABLE public.fact_find_home_contents_ownership OWNER TO postgres;

--
-- Name: fact_find_insurance_policy; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_insurance_policy (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    provider_name text,
    product_name text,
    policy_number text,
    insurance_type text,
    policy_owner_name text,
    policy_establishment_date date,
    renewal_date date,
    expiry_date date,
    cover_amount numeric(18,2),
    premium_total_amount numeric(18,2),
    premium_frequency text,
    premium_structure text,
    policy_fee numeric(18,2),
    smoker_status text,
    waiting_period text,
    benefit_period text,
    tpd_policy_definition text,
    income_protection_policy_definition text,
    held_in_superannuation boolean,
    client_notes text,
    financial_planner_notes text,
    case_id uuid,
    financial_product_id uuid
);


ALTER TABLE public.fact_find_insurance_policy OWNER TO postgres;

--
-- Name: fact_find_insurance_policy_feature; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_insurance_policy_feature (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    insurance_policy_id uuid NOT NULL,
    name text,
    value text
);


ALTER TABLE public.fact_find_insurance_policy_feature OWNER TO postgres;

--
-- Name: fact_find_insurance_policy_item; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_insurance_policy_item (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    insurance_policy_id uuid NOT NULL,
    name text,
    benefit_type text,
    cover_amount numeric(18,2),
    premium_amount numeric(18,2)
);


ALTER TABLE public.fact_find_insurance_policy_item OWNER TO postgres;

--
-- Name: fact_find_insurance_policy_ownership; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_insurance_policy_ownership (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    insurance_policy_id uuid NOT NULL,
    entity_id uuid NOT NULL,
    ownership_percentage numeric(5,2)
);


ALTER TABLE public.fact_find_insurance_policy_ownership OWNER TO postgres;

--
-- Name: fact_find_investment_holding; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_investment_holding (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    investment_option_id uuid NOT NULL,
    investment_platform_id uuid,
    retirement_asset_id uuid,
    superannuation_id uuid,
    quantity numeric(24,8) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT fact_find_investment_holding_check CHECK ((num_nonnulls(investment_platform_id, retirement_asset_id, superannuation_id) = 1)),
    CONSTRAINT fact_find_investment_holding_quantity_check CHECK ((quantity >= (0)::numeric))
);


ALTER TABLE public.fact_find_investment_holding OWNER TO postgres;

--
-- Name: fact_find_investment_income; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_investment_income (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    income_amount numeric(18,2),
    investment_type text,
    income_change_flag boolean,
    income_change_amount numeric(18,2),
    income_change_reason text,
    case_id uuid
);


ALTER TABLE public.fact_find_investment_income OWNER TO postgres;

--
-- Name: fact_find_investment_income_ownership; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_investment_income_ownership (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    investment_income_id uuid NOT NULL,
    entity_id uuid NOT NULL,
    ownership_percentage numeric(5,2),
    created_at timestamp(6) with time zone DEFAULT now() NOT NULL,
    updated_at timestamp(6) with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.fact_find_investment_income_ownership OWNER TO postgres;

--
-- Name: fact_find_investment_platform; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_investment_platform (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    provider_name text,
    product_name text,
    account_number text,
    account_type text,
    account_established_date date,
    opening_balance numeric(18,2),
    account_balance numeric(18,2),
    total_fees numeric(18,2),
    administration_fee_amount numeric(18,2),
    administration_fee_percent numeric(9,4),
    adviser_fee_amount numeric(18,2),
    adviser_fee_percent numeric(9,4),
    trustee_fee_amount numeric(18,2),
    issuer_fee_amount numeric(18,2),
    expense_recovery_fee_amount numeric(18,2),
    expense_recovery_fee_percent numeric(9,4),
    fund_accounting_fee_amount numeric(18,2),
    fund_accounting_fee_percent numeric(9,4),
    asset_fee_percent numeric(9,4),
    contribution_fee_percent numeric(9,4),
    exit_withdrawal_fee_amount numeric(18,2),
    exit_withdrawal_fee_percent numeric(9,4),
    brokerage_buy_fee_amount numeric(18,2),
    brokerage_buy_fee_percent numeric(9,4),
    brokerage_sell_fee_amount numeric(18,2),
    brokerage_sell_fee_percent numeric(9,4),
    buy_sell_spread_amount numeric(18,2),
    switch_fee_amount numeric(18,2),
    client_notes text,
    financial_planner_notes text,
    case_id uuid,
    financial_product_id uuid,
    legacy_account_balance numeric(18,2),
    holdings_configured boolean DEFAULT false NOT NULL
);


ALTER TABLE public.fact_find_investment_platform OWNER TO postgres;

--
-- Name: fact_find_investment_platform_item; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_investment_platform_item (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    investment_platform_id uuid NOT NULL,
    name text,
    fund_option text,
    current_value numeric(18,2),
    allocation_percentage numeric(9,4),
    financial_product_id uuid
);


ALTER TABLE public.fact_find_investment_platform_item OWNER TO postgres;

--
-- Name: fact_find_investment_platform_ownership; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_investment_platform_ownership (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    investment_platform_id uuid NOT NULL,
    entity_id uuid NOT NULL,
    ownership_percentage numeric(5,2)
);


ALTER TABLE public.fact_find_investment_platform_ownership OWNER TO postgres;

--
-- Name: fact_find_occupational_income; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_occupational_income (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    allowance_amount numeric(18,2),
    base_salary numeric(18,2),
    bonus_amount numeric(18,2),
    commission_amount numeric(18,2),
    employment_id uuid,
    salary_sacrifice_amount numeric(18,2),
    superannuation_guarantee_amount numeric(18,2),
    income_change_flag boolean,
    income_change_amount numeric(18,2),
    income_change_reason text,
    case_id uuid
);


ALTER TABLE public.fact_find_occupational_income OWNER TO postgres;

--
-- Name: fact_find_occupational_income_ownership; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_occupational_income_ownership (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    occupational_income_id uuid NOT NULL,
    entity_id uuid NOT NULL,
    ownership_percentage numeric(5,2),
    created_at timestamp(6) with time zone DEFAULT now() NOT NULL,
    updated_at timestamp(6) with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.fact_find_occupational_income_ownership OWNER TO postgres;

--
-- Name: fact_find_other_asset; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_other_asset (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    current_market_value numeric(18,2),
    client_notes text,
    financial_planner_notes text,
    case_id uuid
);


ALTER TABLE public.fact_find_other_asset OWNER TO postgres;

--
-- Name: fact_find_other_asset_ownership; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_other_asset_ownership (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    other_asset_id uuid NOT NULL,
    entity_id uuid NOT NULL,
    ownership_percentage numeric(5,2)
);


ALTER TABLE public.fact_find_other_asset_ownership OWNER TO postgres;

--
-- Name: fact_find_other_income; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_other_income (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    non_taxable_income_amount numeric(18,2),
    source_of_non_taxable_income text,
    taxable_income_amount numeric(18,2),
    taxable_income_flag boolean,
    source_of_taxable_income text,
    income_change_flag boolean,
    income_change_amount numeric(18,2),
    income_change_reason text,
    case_id uuid
);


ALTER TABLE public.fact_find_other_income OWNER TO postgres;

--
-- Name: fact_find_other_income_ownership; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_other_income_ownership (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    other_income_id uuid NOT NULL,
    entity_id uuid NOT NULL,
    ownership_percentage numeric(5,2),
    created_at timestamp(6) with time zone DEFAULT now() NOT NULL,
    updated_at timestamp(6) with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.fact_find_other_income_ownership OWNER TO postgres;

--
-- Name: fact_find_other_liability; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_other_liability (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    liability_type text,
    current_balance numeric(18,2),
    repayment_amount numeric(18,2),
    repayment_frequency text,
    client_notes text,
    financial_planner_notes text,
    case_id uuid
);


ALTER TABLE public.fact_find_other_liability OWNER TO postgres;

--
-- Name: fact_find_other_liability_ownership; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_other_liability_ownership (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    other_liability_id uuid NOT NULL,
    entity_id uuid NOT NULL,
    ownership_percentage numeric(5,2)
);


ALTER TABLE public.fact_find_other_liability_ownership OWNER TO postgres;

--
-- Name: fact_find_personal_loan; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_personal_loan (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    provider text,
    product_name text,
    loan_type text,
    establishment_date date,
    original_loan_amount numeric(18,2),
    current_balance numeric(18,2),
    current_interest_rate numeric(9,4),
    original_loan_term text,
    remaining_loan_term text,
    repayment_amount numeric(18,2),
    repayment_frequency text,
    redraw_amount numeric(18,2),
    redraw_fee numeric(18,2),
    account_fee numeric(18,2),
    monthly_fee numeric(18,2),
    exit_fee numeric(18,2),
    other_fee numeric(18,2),
    guarantor text,
    tax_deductible boolean,
    client_notes text,
    financial_planner_notes text,
    case_id uuid,
    financial_product_id uuid
);


ALTER TABLE public.fact_find_personal_loan OWNER TO postgres;

--
-- Name: fact_find_personal_loan_ownership; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_personal_loan_ownership (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    personal_loan_id uuid NOT NULL,
    entity_id uuid NOT NULL,
    ownership_percentage numeric(5,2)
);


ALTER TABLE public.fact_find_personal_loan_ownership OWNER TO postgres;

--
-- Name: fact_find_principal_residence; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_principal_residence (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    address_line1 text,
    address_line2 text,
    suburb text,
    state text,
    postcode text,
    country text,
    purchase_date date,
    purchase_price numeric(18,2),
    current_market_value numeric(18,2),
    outstanding_loan_value numeric(18,2),
    equity_available numeric(18,2),
    estimated_annual_outgoings numeric(18,2),
    client_notes text,
    financial_planner_notes text,
    case_id uuid
);


ALTER TABLE public.fact_find_principal_residence OWNER TO postgres;

--
-- Name: fact_find_principal_residence_ownership; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_principal_residence_ownership (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    principal_residence_id uuid NOT NULL,
    entity_id uuid NOT NULL,
    ownership_percentage numeric(5,2)
);


ALTER TABLE public.fact_find_principal_residence_ownership OWNER TO postgres;

--
-- Name: fact_find_property_asset; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_property_asset (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    property_type text,
    address_line1 text,
    address_line2 text,
    suburb text,
    state text,
    postcode text,
    country text,
    purchase_date date,
    purchase_price numeric(18,2),
    current_market_value numeric(18,2),
    outstanding_loan_value numeric(18,2),
    equity_available numeric(18,2),
    rental_income_amount numeric(18,2),
    rental_income_frequency text,
    estimated_annual_outgoings numeric(18,2),
    client_notes text,
    financial_planner_notes text,
    case_id uuid
);


ALTER TABLE public.fact_find_property_asset OWNER TO postgres;

--
-- Name: fact_find_property_asset_ownership; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_property_asset_ownership (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    property_asset_id uuid NOT NULL,
    entity_id uuid NOT NULL,
    ownership_percentage numeric(5,2)
);


ALTER TABLE public.fact_find_property_asset_ownership OWNER TO postgres;

--
-- Name: fact_find_property_income; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_property_income (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    income_amount numeric(18,2),
    income_change_flag boolean,
    income_change_amount numeric(18,2),
    income_change_reason text,
    case_id uuid
);


ALTER TABLE public.fact_find_property_income OWNER TO postgres;

--
-- Name: fact_find_property_income_ownership; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_property_income_ownership (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    property_income_id uuid NOT NULL,
    entity_id uuid NOT NULL,
    ownership_percentage numeric(5,2),
    created_at timestamp(6) with time zone DEFAULT now() NOT NULL,
    updated_at timestamp(6) with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.fact_find_property_income_ownership OWNER TO postgres;

--
-- Name: fact_find_property_loan; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_property_loan (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    provider text,
    product_name text,
    loan_type text,
    establishment_date date,
    original_loan_amount numeric(18,2),
    current_balance numeric(18,2),
    current_interest_rate numeric(9,4),
    original_loan_term text,
    remaining_loan_term text,
    repayment_amount numeric(18,2),
    repayment_frequency text,
    redraw_amount numeric(18,2),
    redraw_fee numeric(18,2),
    account_fee numeric(18,2),
    monthly_fee numeric(18,2),
    withdrawal_fee numeric(18,2),
    exit_fee numeric(18,2),
    other_fee numeric(18,2),
    guarantor text,
    tax_deductible boolean,
    client_notes text,
    financial_planner_notes text,
    case_id uuid,
    financial_product_id uuid
);


ALTER TABLE public.fact_find_property_loan OWNER TO postgres;

--
-- Name: fact_find_property_loan_ownership; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_property_loan_ownership (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    property_loan_id uuid NOT NULL,
    entity_id uuid NOT NULL,
    ownership_percentage numeric(5,2)
);


ALTER TABLE public.fact_find_property_loan_ownership OWNER TO postgres;

--
-- Name: fact_find_retirement_asset; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_retirement_asset (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    provider_name text,
    product_name text,
    fund_name text,
    account_number text,
    fund_type text,
    account_established_date date,
    eligible_service_date date,
    expiry_date date,
    opening_balance numeric(18,2),
    account_balance numeric(18,2),
    preserved_amount numeric(18,2),
    unrestricted_non_preserved_amount numeric(18,2),
    taxable_amount numeric(18,2),
    tax_free_amount numeric(18,2),
    pension_type text,
    pension_payment_amount numeric(18,2),
    pension_payment_frequency text,
    total_fees numeric(18,2),
    administration_fee_amount numeric(18,2),
    administration_fee_percent numeric(9,4),
    adviser_fee_amount numeric(18,2),
    contribution_fee_percent numeric(9,4),
    exit_withdrawal_fee_amount numeric(18,2),
    exit_withdrawal_fee_percent numeric(9,4),
    nomination_type text,
    nomination_percentage numeric(9,4),
    client_notes text,
    financial_planner_notes text,
    case_id uuid,
    financial_product_id uuid,
    legacy_account_balance numeric(18,2),
    holdings_configured boolean DEFAULT false NOT NULL
);


ALTER TABLE public.fact_find_retirement_asset OWNER TO postgres;

--
-- Name: fact_find_retirement_asset_item; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_retirement_asset_item (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    retirement_asset_id uuid NOT NULL,
    name text,
    fund_option text,
    current_value numeric(18,2),
    allocation_percentage numeric(9,4),
    financial_product_id uuid
);


ALTER TABLE public.fact_find_retirement_asset_item OWNER TO postgres;

--
-- Name: fact_find_retirement_asset_ownership; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_retirement_asset_ownership (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    retirement_asset_id uuid NOT NULL,
    entity_id uuid NOT NULL,
    ownership_percentage numeric(5,2)
);


ALTER TABLE public.fact_find_retirement_asset_ownership OWNER TO postgres;

--
-- Name: fact_find_retirement_income; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_retirement_income (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    income_type text,
    income_frequency text,
    income_amount numeric(18,2),
    income_change_flag boolean,
    income_change_amount numeric(18,2),
    income_change_reason text,
    case_id uuid
);


ALTER TABLE public.fact_find_retirement_income OWNER TO postgres;

--
-- Name: fact_find_retirement_income_ownership; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_retirement_income_ownership (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    retirement_income_id uuid NOT NULL,
    entity_id uuid NOT NULL,
    ownership_percentage numeric(5,2),
    created_at timestamp(6) with time zone DEFAULT now() NOT NULL,
    updated_at timestamp(6) with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.fact_find_retirement_income_ownership OWNER TO postgres;

--
-- Name: fact_find_superannuation; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_superannuation (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    provider_name text,
    product_name text,
    fund_name text,
    account_number text,
    fund_type text,
    account_established_date date,
    eligible_service_date date,
    expiry_date date,
    opening_balance numeric(18,2),
    account_balance numeric(18,2),
    preserved_amount numeric(18,2),
    unrestricted_non_preserved_amount numeric(18,2),
    taxable_amount numeric(18,2),
    tax_free_amount numeric(18,2),
    super_guarantee_percent numeric(9,4),
    total_fees numeric(18,2),
    administration_fee_amount numeric(18,2),
    administration_fee_percent numeric(9,4),
    adviser_fee_amount numeric(18,2),
    adviser_fee_percent numeric(9,4),
    contribution_fee_amount numeric(18,2),
    contribution_fee_percent numeric(9,4),
    exit_withdrawal_fee_amount numeric(18,2),
    exit_withdrawal_fee_percent numeric(9,4),
    nomination_type text,
    nomination_percentage numeric(9,4),
    insurance_attached boolean,
    client_notes text,
    financial_planner_notes text,
    case_id uuid,
    financial_product_id uuid,
    legacy_account_balance numeric(18,2),
    holdings_configured boolean DEFAULT false NOT NULL
);


ALTER TABLE public.fact_find_superannuation OWNER TO postgres;

--
-- Name: fact_find_superannuation_item; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_superannuation_item (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    superannuation_id uuid NOT NULL,
    name text,
    fund_option text,
    current_value numeric(18,2),
    allocation_percentage numeric(9,4),
    financial_product_id uuid
);


ALTER TABLE public.fact_find_superannuation_item OWNER TO postgres;

--
-- Name: fact_find_superannuation_ownership; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_superannuation_ownership (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    superannuation_id uuid NOT NULL,
    entity_id uuid NOT NULL,
    ownership_percentage numeric(5,2)
);


ALTER TABLE public.fact_find_superannuation_ownership OWNER TO postgres;

--
-- Name: fact_find_vehicle; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_vehicle (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    make text,
    model text,
    purchase_date date,
    purchase_price numeric(18,2),
    current_market_value numeric(18,2),
    estimated_annual_outgoings numeric(18,2),
    client_notes text,
    financial_planner_notes text,
    case_id uuid
);


ALTER TABLE public.fact_find_vehicle OWNER TO postgres;

--
-- Name: fact_find_vehicle_loan; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_vehicle_loan (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    provider text,
    product_name text,
    loan_type text,
    establishment_date date,
    original_loan_amount numeric(18,2),
    current_balance numeric(18,2),
    current_interest_rate numeric(9,4),
    original_loan_term text,
    remaining_loan_term text,
    repayment_amount numeric(18,2),
    repayment_frequency text,
    redraw_amount numeric(18,2),
    redraw_fee numeric(18,2),
    account_fee numeric(18,2),
    monthly_fee numeric(18,2),
    withdrawal_fee numeric(18,2),
    exit_fee numeric(18,2),
    other_fee numeric(18,2),
    guarantor text,
    tax_deductible boolean,
    client_notes text,
    financial_planner_notes text,
    case_id uuid,
    financial_product_id uuid
);


ALTER TABLE public.fact_find_vehicle_loan OWNER TO postgres;

--
-- Name: fact_find_vehicle_loan_ownership; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_vehicle_loan_ownership (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    vehicle_loan_id uuid NOT NULL,
    entity_id uuid NOT NULL,
    ownership_percentage numeric(5,2)
);


ALTER TABLE public.fact_find_vehicle_loan_ownership OWNER TO postgres;

--
-- Name: fact_find_vehicle_ownership; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_find_vehicle_ownership (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    vehicle_id uuid NOT NULL,
    entity_id uuid NOT NULL,
    ownership_percentage numeric(5,2)
);


ALTER TABLE public.fact_find_vehicle_ownership OWNER TO postgres;

--
-- Name: financial_planner; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.financial_planner (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    first_name text NOT NULL,
    last_name text DEFAULT ''::text NOT NULL,
    business_unit_id uuid NOT NULL,
    email text,
    phone text,
    adviser_number text,
    asic_adviser_number text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    job_title text,
    CONSTRAINT financial_planner_first_name_check CHECK ((length(TRIM(BOTH FROM first_name)) > 0))
);


ALTER TABLE public.financial_planner OWNER TO postgres;

--
-- Name: financial_product; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.financial_product (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    provider_name text NOT NULL,
    product_name text NOT NULL,
    product_category text NOT NULL,
    product_subcategory text,
    product_code text,
    external_id text,
    description text,
    is_active boolean DEFAULT true NOT NULL,
    source text DEFAULT 'manual'::text NOT NULL,
    last_synced_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    rex_id integer,
    CONSTRAINT financial_product_product_name_check CHECK ((length(TRIM(BOTH FROM product_name)) > 0)),
    CONSTRAINT financial_product_provider_name_check CHECK ((length(TRIM(BOTH FROM provider_name)) > 0))
);


ALTER TABLE public.financial_product OWNER TO postgres;

--
-- Name: financial_product_category; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.financial_product_category (
    code text NOT NULL,
    name text NOT NULL
);


ALTER TABLE public.financial_product_category OWNER TO postgres;

--
-- Name: goal; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.goal (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    case_id uuid NOT NULL,
    title text NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    goal_type text DEFAULT 'other'::text NOT NULL,
    target_amount numeric(18,2),
    target_date date,
    priority text DEFAULT 'medium'::text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    created_by_user_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT goal_goal_type_check CHECK ((goal_type = ANY (ARRAY['retirement'::text, 'property'::text, 'investment'::text, 'debt_reduction'::text, 'cash_flow'::text, 'education'::text, 'estate_planning'::text, 'insurance'::text, 'lifestyle'::text, 'other'::text]))),
    CONSTRAINT goal_priority_check CHECK ((priority = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text]))),
    CONSTRAINT goal_status_check CHECK ((status = ANY (ARRAY['active'::text, 'achieved'::text, 'deferred'::text, 'cancelled'::text]))),
    CONSTRAINT goal_target_amount_check CHECK ((target_amount >= (0)::numeric)),
    CONSTRAINT goal_title_check CHECK (((length(TRIM(BOTH FROM title)) >= 1) AND (length(TRIM(BOTH FROM title)) <= 200)))
);


ALTER TABLE public.goal OWNER TO postgres;

--
-- Name: investment_option; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.investment_option (
    investment_option_id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(200),
    rex_id integer,
    linked_product integer,
    current_price numeric(24,8),
    CONSTRAINT investment_option_current_price_check CHECK ((current_price >= (0)::numeric))
);


ALTER TABLE public.investment_option OWNER TO postgres;

--
-- Data for Name: business_unit; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.business_unit (id, name, code, description, abn, afsl_number, address, email, phone, parent_business_unit_id, is_active, created_at, updated_at, website) VALUES ('7e841a1e-f7fe-4bfd-b24e-4f86c7a06ff4', 'Legacy planner assignments', 'LEGACY-PLANNERS', 'Unverified legacy identifiers/names. Move planners to their verified business unit before activation.', NULL, NULL, NULL, NULL, NULL, NULL, false, '2026-09-28 06:27:02.116661+00', '2026-09-28 06:27:02.116661+00', NULL);
INSERT INTO public.business_unit (id, name, code, description, abn, afsl_number, address, email, phone, parent_business_unit_id, is_active, created_at, updated_at, website) VALUES ('16788c78-8160-7a75-53f5-8abf8e9fa75e', 'Harbour Fern Wealth Advisory', 'DEMO-SYDNEY', 'Fictional development office; address is not a real practice.', NULL, NULL, 'Suite 8, 125 Fictional Quay, Sydney NSW 2000, Australia', 'office@sydney.example.invalid', '02 5550 0101', NULL, true, '2026-09-01 00:00:00+00', '2026-09-01 00:00:00+00', 'https://sydney.example.invalid');
INSERT INTO public.business_unit (id, name, code, description, abn, afsl_number, address, email, phone, parent_business_unit_id, is_active, created_at, updated_at, website) VALUES ('22a87309-286e-5b1f-7046-bed985bfde53', 'Ironbark Hills Financial Planning', 'DEMO-HILLS', 'Fictional development office; address is not a real practice.', NULL, NULL, 'Level 2, 24 Example Grove, Norwest NSW 2153, Australia', 'office@hills.example.invalid', '02 5550 0102', NULL, true, '2026-09-01 00:00:00+00', '2026-09-01 00:00:00+00', 'https://hills.example.invalid');
INSERT INTO public.business_unit (id, name, code, description, abn, afsl_number, address, email, phone, parent_business_unit_id, is_active, created_at, updated_at, website) VALUES ('1a3bba02-8053-aa10-967f-2a2c561bb7bc', 'Laneway Wattle Advisory', 'DEMO-MELBOURNE', 'Fictional development office; address is not a real practice.', NULL, NULL, 'Suite 5, 86 Sample Lane, Melbourne VIC 3000, Australia', 'office@melbourne.example.invalid', '03 5550 0103', NULL, true, '2026-09-01 00:00:00+00', '2026-09-01 00:00:00+00', 'https://melbourne.example.invalid');
INSERT INTO public.business_unit (id, name, code, description, abn, afsl_number, address, email, phone, parent_business_unit_id, is_active, created_at, updated_at, website) VALUES ('9b1d9b94-6eba-2378-f765-752aeb2afed4', 'River Acacia Wealth Management', 'DEMO-BRISBANE', 'Fictional development office; address is not a real practice.', NULL, NULL, 'Level 3, 45 Demonstration Terrace, Brisbane QLD 4000, Australia', 'office@brisbane.example.invalid', '07 5550 0104', NULL, true, '2026-09-01 00:00:00+00', '2026-09-01 00:00:00+00', 'https://brisbane.example.invalid');
INSERT INTO public.business_unit (id, name, code, description, abn, afsl_number, address, email, phone, parent_business_unit_id, is_active, created_at, updated_at, website) VALUES ('3a1bde9b-e983-2088-4193-ab580932dfdf', 'Southern Fern Financial Planning', 'DEMO-BOUTIQUE', 'Fictional development office; address is not a real practice.', NULL, NULL, '12 Imaginary Walk, Hobart TAS 7000, Australia', 'office@boutique.example.invalid', '03 5550 0105', NULL, true, '2026-09-01 00:00:00+00', '2026-09-01 00:00:00+00', 'https://boutique.example.invalid');


--
-- Data for Name: case_entity; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.case_entity (case_id, entity_id, role, details_snapshot) VALUES ('6e7ac885-bf77-40d9-bb9a-7a827827bf66', '0214f9b3-de82-52b5-b213-b825b2dfdf7c', 'client', '{"id": "0214f9b3-de82-52b5-b213-b825b2dfdf7c", "contact": {"id": "0214f9b3-de82-52b5-b213-b825b2dfdf7c", "state": "NSW", "email1": "noah@example.test", "email2": null, "gender": null, "suburb": "Newcastle", "country": "Australia", "fullName": "Noah Williams", "lastName": "Williams", "postCode": "2300", "birthDate": "1978-07-05", "createdAt": "2026-09-23T04:01:39.350679+00:00", "entity_id": "0214f9b3-de82-52b5-b213-b825b2dfdf7c", "firstName": "Noah", "phoneHome": null, "phoneWork": null, "updatedAt": "2026-10-06T07:50:25.958512+00:00", "middleName": null, "salutation": null, "mobilePhone": null, "addressLine1": null, "addressLine2": null, "maritalStatus": "Divorced", "taxFileNumber": null, "businessUnitId": null, "taxResidentFlag": true, "financialPlannerId": "94a2d4e1-a05d-f1d4-49f9-e62f58e317fc", "postalSameAsResidential": true}, "created_at": "2026-09-25T13:09:30.788267+00:00", "updated_at": "2026-10-06T07:50:25.958512+00:00", "entity_type": "individual", "display_name": "Noah Williams", "financial_planner_id": "834dc56d-7ac9-4c1a-bb47-4030aaecbebb"}');
INSERT INTO public.case_entity (case_id, entity_id, role, details_snapshot) VALUES ('6e7ac885-bf77-40d9-bb9a-7a827827bf66', '21340348-85a1-c72f-bdf1-0860c21d4b54', 'client', '{"id": "21340348-85a1-c72f-bdf1-0860c21d4b54", "contact": {"id": "21340348-85a1-c72f-bdf1-0860c21d4b54", "state": "NSW", "email1": "amelia.hartley@example.invalid", "email2": null, "gender": null, "suburb": "Lane Cove", "country": "Australia", "fullName": "Amelia Hartley", "lastName": "Hartley", "postCode": "2066", "birthDate": "1982-04-18", "createdAt": "2026-09-26T09:26:41.563295+00:00", "entity_id": "21340348-85a1-c72f-bdf1-0860c21d4b54", "firstName": "Amelia", "phoneHome": null, "phoneWork": null, "updatedAt": "2026-09-29T15:44:39.001448+00:00", "middleName": null, "salutation": null, "mobilePhone": null, "addressLine1": "18 Banksia Crescent", "addressLine2": null, "maritalStatus": "Married", "taxFileNumber": null, "businessUnitId": "16788c78-8160-7a75-53f5-8abf8e9fa75e", "taxResidentFlag": true, "financialPlannerId": "dfa5a8f7-56c8-97d2-dcf0-39c2da5b0d1d", "postalSameAsResidential": true}, "created_at": "2026-09-26T09:26:41.563295+00:00", "updated_at": "2026-09-29T15:45:54.624575+00:00", "entity_type": "individual", "display_name": "Amelia Hartley", "financial_planner_id": "dfa5a8f7-56c8-97d2-dcf0-39c2da5b0d1d"}');


--
-- Data for Name: case_financial_planner; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.case_financial_planner (case_id, financial_planner_id, is_primary, created_at) VALUES ('6e7ac885-bf77-40d9-bb9a-7a827827bf66', 'dfa5a8f7-56c8-97d2-dcf0-39c2da5b0d1d', true, '2026-10-06 08:03:27.392576+00');


--
-- Data for Name: contact; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.contact (id, "createdAt", "updatedAt", "firstName", "middleName", "lastName", "fullName", salutation, "birthDate", email1, email2, "mobilePhone", "phoneHome", "phoneWork", gender, "maritalStatus", "addressLine1", "addressLine2", suburb, state, "postCode", country, "postalSameAsResidential", "taxResidentFlag", "taxFileNumber", "businessUnitId", "financialPlannerId", entity_id) VALUES ('2fd1c862-d355-514c-a415-c30dd66168ef', '2026-09-23 04:01:39.350679+00', '2026-09-25 13:09:30.788267+00', 'Jack', NULL, 'O''Brien', 'Jack O''Brien', NULL, '1983-12-07', 'jack@example.test', NULL, NULL, NULL, NULL, NULL, 'Single', NULL, NULL, 'Geelong', 'VIC', '3220', 'Australia', true, true, NULL, NULL, '834dc56d-7ac9-4c1a-bb47-4030aaecbebb', '2fd1c862-d355-514c-a415-c30dd66168ef');
INSERT INTO public.contact (id, "createdAt", "updatedAt", "firstName", "middleName", "lastName", "fullName", salutation, "birthDate", email1, email2, "mobilePhone", "phoneHome", "phoneWork", gender, "maritalStatus", "addressLine1", "addressLine2", suburb, state, "postCode", country, "postalSameAsResidential", "taxResidentFlag", "taxFileNumber", "businessUnitId", "financialPlannerId", entity_id) VALUES ('e2fb9ead-5c3d-5f07-9030-2eb109ea027b', '2026-09-23 04:01:39.350679+00', '2026-09-25 13:09:30.788267+00', 'Ava', NULL, 'Patel', 'Ava Patel', NULL, '1992-02-17', 'ava@example.test', NULL, NULL, NULL, NULL, NULL, 'Single', NULL, NULL, 'Sydney', 'NSW', '2000', 'Australia', true, true, NULL, NULL, '834dc56d-7ac9-4c1a-bb47-4030aaecbebb', 'e2fb9ead-5c3d-5f07-9030-2eb109ea027b');
INSERT INTO public.contact (id, "createdAt", "updatedAt", "firstName", "middleName", "lastName", "fullName", salutation, "birthDate", email1, email2, "mobilePhone", "phoneHome", "phoneWork", gender, "maritalStatus", "addressLine1", "addressLine2", suburb, state, "postCode", country, "postalSameAsResidential", "taxResidentFlag", "taxFileNumber", "businessUnitId", "financialPlannerId", entity_id) VALUES ('f9438f7c-a8e5-5839-8673-057ba714d3a0', '2026-09-23 04:01:39.350679+00', '2026-09-25 13:09:30.788267+00', 'Harper', NULL, 'Scott', 'Harper Scott', NULL, '1963-10-02', 'harper@example.test', NULL, NULL, NULL, NULL, NULL, 'Widowed', NULL, NULL, 'Hobart', 'TAS', '7000', 'Australia', true, true, NULL, NULL, '834dc56d-7ac9-4c1a-bb47-4030aaecbebb', 'f9438f7c-a8e5-5839-8673-057ba714d3a0');
INSERT INTO public.contact (id, "createdAt", "updatedAt", "firstName", "middleName", "lastName", "fullName", salutation, "birthDate", email1, email2, "mobilePhone", "phoneHome", "phoneWork", gender, "maritalStatus", "addressLine1", "addressLine2", suburb, state, "postCode", country, "postalSameAsResidential", "taxResidentFlag", "taxFileNumber", "businessUnitId", "financialPlannerId", entity_id) VALUES ('aff315ca-e674-5e50-8a58-b4b697c78301', '2026-09-23 04:01:39.350679+00', '2026-09-25 13:09:30.788267+00', 'Sofia', NULL, 'Rivera', 'Sofia Rivera', NULL, '1995-05-21', 'sofia@example.test', NULL, NULL, NULL, NULL, NULL, 'Single', NULL, NULL, 'Brisbane', 'QLD', '4000', 'Australia', true, true, NULL, NULL, '834dc56d-7ac9-4c1a-bb47-4030aaecbebb', 'aff315ca-e674-5e50-8a58-b4b697c78301');
INSERT INTO public.contact (id, "createdAt", "updatedAt", "firstName", "middleName", "lastName", "fullName", salutation, "birthDate", email1, email2, "mobilePhone", "phoneHome", "phoneWork", gender, "maritalStatus", "addressLine1", "addressLine2", suburb, state, "postCode", country, "postalSameAsResidential", "taxResidentFlag", "taxFileNumber", "businessUnitId", "financialPlannerId", entity_id) VALUES ('ea87fa5d-abe4-5a46-b31e-d036cc2abc8a', '2026-09-23 04:01:39.350679+00', '2026-09-25 13:09:30.788267+00', 'Priya', NULL, 'Brown', 'Priya Brown', NULL, '1977-06-23', 'priya@example.test', NULL, NULL, NULL, NULL, NULL, 'Married', NULL, NULL, 'Perth', 'WA', '6000', 'Australia', true, true, NULL, NULL, '834dc56d-7ac9-4c1a-bb47-4030aaecbebb', 'ea87fa5d-abe4-5a46-b31e-d036cc2abc8a');
INSERT INTO public.contact (id, "createdAt", "updatedAt", "firstName", "middleName", "lastName", "fullName", salutation, "birthDate", email1, email2, "mobilePhone", "phoneHome", "phoneWork", gender, "maritalStatus", "addressLine1", "addressLine2", suburb, state, "postCode", country, "postalSameAsResidential", "taxResidentFlag", "taxFileNumber", "businessUnitId", "financialPlannerId", entity_id) VALUES ('d40656e0-fd5c-584f-8452-c9d8ce20610d', '2026-09-23 04:01:39.350679+00', '2026-09-25 13:09:30.788267+00', 'Liam', NULL, 'Nguyen', 'Liam Nguyen', NULL, '1986-09-24', 'liam@example.test', NULL, NULL, NULL, NULL, NULL, 'Married', NULL, NULL, 'Parramatta', 'NSW', '2150', 'Australia', true, true, NULL, NULL, '834dc56d-7ac9-4c1a-bb47-4030aaecbebb', 'd40656e0-fd5c-584f-8452-c9d8ce20610d');
INSERT INTO public.contact (id, "createdAt", "updatedAt", "firstName", "middleName", "lastName", "fullName", salutation, "birthDate", email1, email2, "mobilePhone", "phoneHome", "phoneWork", gender, "maritalStatus", "addressLine1", "addressLine2", suburb, state, "postCode", country, "postalSameAsResidential", "taxResidentFlag", "taxFileNumber", "businessUnitId", "financialPlannerId", entity_id) VALUES ('8b0ef68e-dba1-57ee-9af3-50f7839669a4', '2026-09-23 04:01:39.350679+00', '2026-09-25 13:09:30.788267+00', 'Ethan', NULL, 'Brown', 'Ethan Brown', NULL, '1975-01-11', 'ethan@example.test', NULL, NULL, NULL, NULL, NULL, 'Married', NULL, NULL, 'Perth', 'WA', '6000', 'Australia', true, true, NULL, NULL, '834dc56d-7ac9-4c1a-bb47-4030aaecbebb', '8b0ef68e-dba1-57ee-9af3-50f7839669a4');
INSERT INTO public.contact (id, "createdAt", "updatedAt", "firstName", "middleName", "lastName", "fullName", salutation, "birthDate", email1, email2, "mobilePhone", "phoneHome", "phoneWork", gender, "maritalStatus", "addressLine1", "addressLine2", suburb, state, "postCode", country, "postalSameAsResidential", "taxResidentFlag", "taxFileNumber", "businessUnitId", "financialPlannerId", entity_id) VALUES ('1a2b7fd2-5f8f-5d8c-baf3-0e2ecf017997', '2026-09-23 04:01:39.350679+00', '2026-09-25 13:09:30.788267+00', 'Ella', NULL, 'Hassan', 'Ella Hassan', NULL, '1990-08-29', 'ella@example.test', NULL, NULL, NULL, NULL, NULL, 'Single', NULL, NULL, 'Adelaide', 'SA', '5000', 'Australia', true, true, NULL, NULL, '834dc56d-7ac9-4c1a-bb47-4030aaecbebb', '1a2b7fd2-5f8f-5d8c-baf3-0e2ecf017997');
INSERT INTO public.contact (id, "createdAt", "updatedAt", "firstName", "middleName", "lastName", "fullName", salutation, "birthDate", email1, email2, "mobilePhone", "phoneHome", "phoneWork", gender, "maritalStatus", "addressLine1", "addressLine2", suburb, state, "postCode", country, "postalSameAsResidential", "taxResidentFlag", "taxFileNumber", "businessUnitId", "financialPlannerId", entity_id) VALUES ('b15a9373-b775-5211-afbf-1bceea904a95', '2026-09-23 04:01:39.350679+00', '2026-09-25 13:09:30.788267+00', 'Grace', NULL, 'Chen', 'Grace Chen', NULL, '1959-11-03', 'grace@example.test', NULL, NULL, NULL, NULL, NULL, 'Married', NULL, NULL, 'Melbourne', 'VIC', '3000', 'Australia', true, true, NULL, NULL, '834dc56d-7ac9-4c1a-bb47-4030aaecbebb', 'b15a9373-b775-5211-afbf-1bceea904a95');
INSERT INTO public.contact (id, "createdAt", "updatedAt", "firstName", "middleName", "lastName", "fullName", salutation, "birthDate", email1, email2, "mobilePhone", "phoneHome", "phoneWork", gender, "maritalStatus", "addressLine1", "addressLine2", suburb, state, "postCode", country, "postalSameAsResidential", "taxResidentFlag", "taxFileNumber", "businessUnitId", "financialPlannerId", entity_id) VALUES ('4472ba0b-7901-5e0e-af0a-812c347e574f', '2026-09-23 04:01:39.350679+00', '2026-09-25 13:09:30.788267+00', 'Maya', NULL, 'Nguyen', 'Maya Nguyen', NULL, '1988-04-12', 'maya@example.test', NULL, NULL, NULL, NULL, NULL, 'Married', NULL, NULL, 'Parramatta', 'NSW', '2150', 'Australia', true, true, NULL, NULL, '834dc56d-7ac9-4c1a-bb47-4030aaecbebb', '4472ba0b-7901-5e0e-af0a-812c347e574f');
INSERT INTO public.contact (id, "createdAt", "updatedAt", "firstName", "middleName", "lastName", "fullName", salutation, "birthDate", email1, email2, "mobilePhone", "phoneHome", "phoneWork", gender, "maritalStatus", "addressLine1", "addressLine2", suburb, state, "postCode", country, "postalSameAsResidential", "taxResidentFlag", "taxFileNumber", "businessUnitId", "financialPlannerId", entity_id) VALUES ('a97799ee-e702-5031-ad8f-b80d762cec5a', '2026-09-23 04:01:39.350679+00', '2026-09-25 13:09:30.788267+00', 'Owen', NULL, 'Chen', 'Owen Chen', NULL, '1957-03-19', 'owen@example.test', NULL, NULL, NULL, NULL, NULL, 'Married', NULL, NULL, 'Melbourne', 'VIC', '3000', 'Australia', true, true, NULL, NULL, '834dc56d-7ac9-4c1a-bb47-4030aaecbebb', 'a97799ee-e702-5031-ad8f-b80d762cec5a');
INSERT INTO public.contact (id, "createdAt", "updatedAt", "firstName", "middleName", "lastName", "fullName", salutation, "birthDate", email1, email2, "mobilePhone", "phoneHome", "phoneWork", gender, "maritalStatus", "addressLine1", "addressLine2", suburb, state, "postCode", country, "postalSameAsResidential", "taxResidentFlag", "taxFileNumber", "businessUnitId", "financialPlannerId", entity_id) VALUES ('4a692464-d076-5c32-b162-63dcff4268f8', '2026-09-24 07:46:51.639994+00', '2026-09-25 13:09:30.788267+00', 'John', NULL, 'Smith', 'John Smith', NULL, '1985-08-14', 'john.smith@example.com', NULL, '0412345678', NULL, NULL, NULL, 'Married', '12 Example Street', NULL, 'Castle Hill', 'NSW', '2154', 'Australia', true, NULL, NULL, NULL, NULL, '4a692464-d076-5c32-b162-63dcff4268f8');
INSERT INTO public.contact (id, "createdAt", "updatedAt", "firstName", "middleName", "lastName", "fullName", salutation, "birthDate", email1, email2, "mobilePhone", "phoneHome", "phoneWork", gender, "maritalStatus", "addressLine1", "addressLine2", suburb, state, "postCode", country, "postalSameAsResidential", "taxResidentFlag", "taxFileNumber", "businessUnitId", "financialPlannerId", entity_id) VALUES ('f5c5e9a6-2d1c-5e46-b2a1-46e684e46995', '2026-09-24 07:46:51.639994+00', '2026-09-25 13:09:30.788267+00', 'Jane', NULL, 'Smith', 'Jane Smith', NULL, '1987-05-02', 'jane.smith@example.com', NULL, '0412987654', NULL, NULL, NULL, 'Married', '12 Example Street', NULL, 'Castle Hill', 'NSW', '2154', 'Australia', true, NULL, NULL, NULL, NULL, 'f5c5e9a6-2d1c-5e46-b2a1-46e684e46995');
INSERT INTO public.contact (id, "createdAt", "updatedAt", "firstName", "middleName", "lastName", "fullName", salutation, "birthDate", email1, email2, "mobilePhone", "phoneHome", "phoneWork", gender, "maritalStatus", "addressLine1", "addressLine2", suburb, state, "postCode", country, "postalSameAsResidential", "taxResidentFlag", "taxFileNumber", "businessUnitId", "financialPlannerId", entity_id) VALUES ('c4406eb7-c031-5f29-ab93-beea11e18887', '2026-09-24 07:46:51.639994+00', '2026-09-25 13:09:30.788267+00', 'Michael', NULL, 'Brown', 'Michael Brown', NULL, '1972-11-20', 'michael.brown@example.com', NULL, '0400111222', NULL, NULL, NULL, 'Single', '8 Harbour Road', NULL, 'Newcastle', 'NSW', '2300', 'Australia', true, NULL, NULL, NULL, NULL, 'c4406eb7-c031-5f29-ab93-beea11e18887');
INSERT INTO public.contact (id, "createdAt", "updatedAt", "firstName", "middleName", "lastName", "fullName", salutation, "birthDate", email1, email2, "mobilePhone", "phoneHome", "phoneWork", gender, "maritalStatus", "addressLine1", "addressLine2", suburb, state, "postCode", country, "postalSameAsResidential", "taxResidentFlag", "taxFileNumber", "businessUnitId", "financialPlannerId", entity_id) VALUES ('21340348-85a1-c72f-bdf1-0860c21d4b54', '2026-09-26 09:26:41.563295+00', '2026-09-29 15:44:39.001448+00', 'Amelia', NULL, 'Hartley', 'Amelia Hartley', NULL, '1982-04-18', 'amelia.hartley@example.invalid', NULL, NULL, NULL, NULL, NULL, 'Married', '18 Banksia Crescent', NULL, 'Lane Cove', 'NSW', '2066', 'Australia', true, true, NULL, '16788c78-8160-7a75-53f5-8abf8e9fa75e', 'dfa5a8f7-56c8-97d2-dcf0-39c2da5b0d1d', '21340348-85a1-c72f-bdf1-0860c21d4b54');
INSERT INTO public.contact (id, "createdAt", "updatedAt", "firstName", "middleName", "lastName", "fullName", salutation, "birthDate", email1, email2, "mobilePhone", "phoneHome", "phoneWork", gender, "maritalStatus", "addressLine1", "addressLine2", suburb, state, "postCode", country, "postalSameAsResidential", "taxResidentFlag", "taxFileNumber", "businessUnitId", "financialPlannerId", entity_id) VALUES ('928618c6-fbe9-cefb-b909-8749139aba74', '2026-09-26 09:26:41.563295+00', '2026-09-29 15:44:39.001448+00', 'Daniel', NULL, 'Hartley', 'Daniel Hartley', NULL, '1980-11-06', 'daniel.hartley@example.invalid', NULL, NULL, NULL, NULL, NULL, 'Married', '18 Banksia Crescent', NULL, 'Lane Cove', 'NSW', '2066', 'Australia', true, true, NULL, '16788c78-8160-7a75-53f5-8abf8e9fa75e', 'dfa5a8f7-56c8-97d2-dcf0-39c2da5b0d1d', '928618c6-fbe9-cefb-b909-8749139aba74');
INSERT INTO public.contact (id, "createdAt", "updatedAt", "firstName", "middleName", "lastName", "fullName", salutation, "birthDate", email1, email2, "mobilePhone", "phoneHome", "phoneWork", gender, "maritalStatus", "addressLine1", "addressLine2", suburb, state, "postCode", country, "postalSameAsResidential", "taxResidentFlag", "taxFileNumber", "businessUnitId", "financialPlannerId", entity_id) VALUES ('5876e49c-a05e-e482-b1c4-109d4f0d768f', '2026-09-26 09:26:41.563295+00', '2026-09-29 15:44:39.001448+00', 'Priya', NULL, 'Nair', 'Priya Nair', NULL, '1987-08-22', 'priya.nair@example.invalid', NULL, NULL, NULL, NULL, NULL, 'Single', '42 Myrtle Street', NULL, 'Richmond', 'VIC', '3121', 'Australia', true, true, NULL, '1a3bba02-8053-aa10-967f-2a2c561bb7bc', '4017ffe1-b404-db14-18d1-e84fa4fde325', '5876e49c-a05e-e482-b1c4-109d4f0d768f');
INSERT INTO public.contact (id, "createdAt", "updatedAt", "firstName", "middleName", "lastName", "fullName", salutation, "birthDate", email1, email2, "mobilePhone", "phoneHome", "phoneWork", gender, "maritalStatus", "addressLine1", "addressLine2", suburb, state, "postCode", country, "postalSameAsResidential", "taxResidentFlag", "taxFileNumber", "businessUnitId", "financialPlannerId", entity_id) VALUES ('ddbc9aa9-d048-17b2-5335-9682d9601396', '2026-09-26 09:26:41.563295+00', '2026-09-29 15:44:39.001448+00', 'Lucas', NULL, 'Bennett', 'Lucas Bennett', NULL, '1991-02-13', 'lucas.bennett@example.invalid', NULL, NULL, NULL, NULL, NULL, 'Single', '7 Fern Avenue', NULL, 'Newcastle', 'NSW', '2300', 'Australia', true, true, NULL, '22a87309-286e-5b1f-7046-bed985bfde53', '14701153-ca74-f338-6439-4bcefdef14aa', 'ddbc9aa9-d048-17b2-5335-9682d9601396');
INSERT INTO public.contact (id, "createdAt", "updatedAt", "firstName", "middleName", "lastName", "fullName", salutation, "birthDate", email1, email2, "mobilePhone", "phoneHome", "phoneWork", gender, "maritalStatus", "addressLine1", "addressLine2", suburb, state, "postCode", country, "postalSameAsResidential", "taxResidentFlag", "taxFileNumber", "businessUnitId", "financialPlannerId", entity_id) VALUES ('e5a1a5da-551a-79fd-6753-e37c8f4df498', '2026-09-26 09:26:41.563295+00', '2026-09-29 15:44:39.001448+00', 'Margaret', NULL, 'Ellison', 'Margaret Ellison', NULL, '1958-06-29', 'margaret.ellison@example.invalid', NULL, NULL, NULL, NULL, NULL, 'Widowed', '26 Garden Terrace', NULL, 'Adelaide', 'SA', '5000', 'Australia', true, true, NULL, '3a1bde9b-e983-2088-4193-ab580932dfdf', '84c2d8a4-cce1-a3c0-981c-92092ece7572', 'e5a1a5da-551a-79fd-6753-e37c8f4df498');
INSERT INTO public.contact (id, "createdAt", "updatedAt", "firstName", "middleName", "lastName", "fullName", salutation, "birthDate", email1, email2, "mobilePhone", "phoneHome", "phoneWork", gender, "maritalStatus", "addressLine1", "addressLine2", suburb, state, "postCode", country, "postalSameAsResidential", "taxResidentFlag", "taxFileNumber", "businessUnitId", "financialPlannerId", entity_id) VALUES ('24b01170-25fe-d82b-dfe4-1ec38494ac0f', '2026-09-26 09:26:41.563295+00', '2026-09-29 15:44:39.001448+00', 'Ella', NULL, 'Tran', 'Ella Tran', NULL, NULL, 'ella.tran@example.invalid', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, true, NULL, NULL, '1a3bba02-8053-aa10-967f-2a2c561bb7bc', '5e6c9ee8-3e7d-43ca-dbd6-75a41c90d78b', '24b01170-25fe-d82b-dfe4-1ec38494ac0f');
INSERT INTO public.contact (id, "createdAt", "updatedAt", "firstName", "middleName", "lastName", "fullName", salutation, "birthDate", email1, email2, "mobilePhone", "phoneHome", "phoneWork", gender, "maritalStatus", "addressLine1", "addressLine2", suburb, state, "postCode", country, "postalSameAsResidential", "taxResidentFlag", "taxFileNumber", "businessUnitId", "financialPlannerId", entity_id) VALUES ('89c9b482-62a4-4b1b-fadb-8947c86522b1', '2026-09-26 09:26:41.563295+00', '2026-09-29 15:44:39.001448+00', 'Noah', NULL, 'Mercer', 'Noah Mercer', NULL, '1997-09-12', 'noah.mercer@example.invalid', NULL, NULL, NULL, NULL, NULL, 'Single', '11 Acacia Lane', NULL, 'Brisbane', 'QLD', '4000', 'Australia', true, true, NULL, '9b1d9b94-6eba-2378-f765-752aeb2afed4', '74f7b4ff-015c-602f-0992-eb94ae05723d', '89c9b482-62a4-4b1b-fadb-8947c86522b1');
INSERT INTO public.contact (id, "createdAt", "updatedAt", "firstName", "middleName", "lastName", "fullName", salutation, "birthDate", email1, email2, "mobilePhone", "phoneHome", "phoneWork", gender, "maritalStatus", "addressLine1", "addressLine2", suburb, state, "postCode", country, "postalSameAsResidential", "taxResidentFlag", "taxFileNumber", "businessUnitId", "financialPlannerId", entity_id) VALUES ('0214f9b3-de82-52b5-b213-b825b2dfdf7c', '2026-09-23 04:01:39.350679+00', '2026-10-06 07:50:25.958512+00', 'Noah', NULL, 'Williams', 'Noah Williams', NULL, '1978-07-05', 'noah@example.test', NULL, NULL, NULL, NULL, NULL, 'Divorced', NULL, NULL, 'Newcastle', 'NSW', '2300', 'Australia', true, true, NULL, NULL, '94a2d4e1-a05d-f1d4-49f9-e62f58e317fc', '0214f9b3-de82-52b5-b213-b825b2dfdf7c');


--
-- Data for Name: crm_case; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.crm_case (id, name, status, captured_at, created_at, updated_at, case_number, advice_type, financial_planner) VALUES ('6e7ac885-bf77-40d9-bb9a-7a827827bf66', 'Initial advice', 'open', '2026-10-06 08:03:27.392576+00', '2026-10-06 08:03:27.392576+00', '2026-10-06 08:03:27.392576+00', 1005, 'Initial', NULL);


--
-- Data for Name: crm_migration; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.crm_migration (name, applied_at) VALUES ('crm_context_v1', '2026-09-25 13:09:30.788267+00');
INSERT INTO public.crm_migration (name, applied_at) VALUES ('entity_types_v2', '2026-09-26 07:04:17.408831+00');
INSERT INTO public.crm_migration (name, applied_at) VALUES ('advice_cases_v1', '2026-09-28 05:57:37.89612+00');
INSERT INTO public.crm_migration (name, applied_at) VALUES ('planner_directory_v1', '2026-09-28 06:27:02.116661+00');
INSERT INTO public.crm_migration (name, applied_at) VALUES ('case_goals_v1', '2026-10-06 08:33:27.293874+00');
INSERT INTO public.crm_migration (name, applied_at) VALUES ('investment_holdings_v1', '2026-10-07 01:29:49.497965+00');


--
-- Data for Name: crm_note; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.crm_note (id, entity_id, case_id, title, body, created_by_user_id, created_at, updated_at) VALUES ('601499a8-3462-65bc-edba-0a41edad8891', '21340348-85a1-c72f-bdf1-0860c21d4b54', NULL, 'Annual review priorities', 'Review retirement contributions, mortgage offsets and protection needs. All figures are fictional demonstration data.', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00');
INSERT INTO public.crm_note (id, entity_id, case_id, title, body, created_by_user_id, created_at, updated_at) VALUES ('c8bdd53a-8103-24bb-b470-d496e1826bfa', '5876e49c-a05e-e482-b1c4-109d4f0d768f', NULL, 'Investment planning discussion', 'Explore a diversified long-term portfolio and establish a cash reserve for variable practice income.', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00');
INSERT INTO public.crm_note (id, entity_id, case_id, title, body, created_by_user_id, created_at, updated_at) VALUES ('ce812b90-f350-a68d-325c-946c273e6e7d', 'ddbc9aa9-d048-17b2-5335-9682d9601396', NULL, 'Liability review', 'Compare repayment priorities across the cards, personal loan and vehicle finance.', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00');
INSERT INTO public.crm_note (id, entity_id, case_id, title, body, created_by_user_id, created_at, updated_at) VALUES ('32df35ad-1a85-1807-5f33-932038f79269', 'e5a1a5da-551a-79fd-6753-e37c8f4df498', NULL, 'Retirement cash flow', 'Review pension drawdowns and maintain two years of planned spending in accessible reserves.', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00');
INSERT INTO public.crm_note (id, entity_id, case_id, title, body, created_by_user_id, created_at, updated_at) VALUES ('006f714d-b9dc-4786-b7fc-73deac8da38a', '0214f9b3-de82-52b5-b213-b825b2dfdf7c', NULL, 'do this and that', 'hello', NULL, '2026-09-29 15:36:03.668277+00', '2026-09-29 15:36:03.668277+00');


--
-- Data for Name: crm_task; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.crm_task (id, entity_id, case_id, title, description, due_date, completed_at, assigned_to_user_id, created_by_user_id, created_at, updated_at) VALUES ('d87d1fe7-9998-63fe-6653-0dc1a74c55d4', '21340348-85a1-c72f-bdf1-0860c21d4b54', NULL, 'Obtain latest super statements', 'Confirm balances and beneficiary nominations before the annual review.', '2026-10-15', NULL, NULL, NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00');
INSERT INTO public.crm_task (id, entity_id, case_id, title, description, due_date, completed_at, assigned_to_user_id, created_by_user_id, created_at, updated_at) VALUES ('225adcba-6221-42dc-8ecf-0dd5a69e5e9b', '0214f9b3-de82-52b5-b213-b825b2dfdf7c', NULL, 'Generate this mfs soa', 'do it lad
', NULL, NULL, NULL, NULL, '2026-09-29 15:35:45.823262+00', '2026-09-29 15:35:45.823262+00');


--
-- Data for Name: entity; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.entity (id, entity_type, display_name, created_at, updated_at, financial_planner_id) VALUES ('0214f9b3-de82-52b5-b213-b825b2dfdf7c', 'individual', 'Noah Williams', '2026-09-25 13:09:30.788267+00', '2026-10-06 07:50:25.958512+00', '834dc56d-7ac9-4c1a-bb47-4030aaecbebb');
INSERT INTO public.entity (id, entity_type, display_name, created_at, updated_at, financial_planner_id) VALUES ('9528a13b-8bd4-4fc1-9db7-7214a931b13d', 'joint', 'Smith Family', '2026-09-26 07:59:22.20841+00', '2026-09-26 07:59:22.20841+00', NULL);
INSERT INTO public.entity (id, entity_type, display_name, created_at, updated_at, financial_planner_id) VALUES ('3785316a-69e5-ad58-745e-ce8512001a71', 'family_trust', 'Hartley Family Trust', '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00', 'dfa5a8f7-56c8-97d2-dcf0-39c2da5b0d1d');
INSERT INTO public.entity (id, entity_type, display_name, created_at, updated_at, financial_planner_id) VALUES ('ed645525-e3fb-adf1-f9f7-f91555fe272e', 'company', 'Hartley Design Studio Pty Ltd', '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00', 'bd49d568-8006-e2c8-3520-9afeb4a7a044');
INSERT INTO public.entity (id, entity_type, display_name, created_at, updated_at, financial_planner_id) VALUES ('9707491d-65ca-c4c7-13d0-5b2bab871dc1', 'joint', 'Amelia and Daniel Hartley', '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00', 'dfa5a8f7-56c8-97d2-dcf0-39c2da5b0d1d');
INSERT INTO public.entity (id, entity_type, display_name, created_at, updated_at, financial_planner_id) VALUES ('2fd1c862-d355-514c-a415-c30dd66168ef', 'individual', 'Jack O''Brien', '2026-09-25 13:09:30.788267+00', '2026-09-25 13:09:30.788267+00', '834dc56d-7ac9-4c1a-bb47-4030aaecbebb');
INSERT INTO public.entity (id, entity_type, display_name, created_at, updated_at, financial_planner_id) VALUES ('e2fb9ead-5c3d-5f07-9030-2eb109ea027b', 'individual', 'Ava Patel', '2026-09-25 13:09:30.788267+00', '2026-09-25 13:09:30.788267+00', '834dc56d-7ac9-4c1a-bb47-4030aaecbebb');
INSERT INTO public.entity (id, entity_type, display_name, created_at, updated_at, financial_planner_id) VALUES ('f9438f7c-a8e5-5839-8673-057ba714d3a0', 'individual', 'Harper Scott', '2026-09-25 13:09:30.788267+00', '2026-09-25 13:09:30.788267+00', '834dc56d-7ac9-4c1a-bb47-4030aaecbebb');
INSERT INTO public.entity (id, entity_type, display_name, created_at, updated_at, financial_planner_id) VALUES ('aff315ca-e674-5e50-8a58-b4b697c78301', 'individual', 'Sofia Rivera', '2026-09-25 13:09:30.788267+00', '2026-09-25 13:09:30.788267+00', '834dc56d-7ac9-4c1a-bb47-4030aaecbebb');
INSERT INTO public.entity (id, entity_type, display_name, created_at, updated_at, financial_planner_id) VALUES ('ea87fa5d-abe4-5a46-b31e-d036cc2abc8a', 'individual', 'Priya Brown', '2026-09-25 13:09:30.788267+00', '2026-09-25 13:09:30.788267+00', '834dc56d-7ac9-4c1a-bb47-4030aaecbebb');
INSERT INTO public.entity (id, entity_type, display_name, created_at, updated_at, financial_planner_id) VALUES ('d40656e0-fd5c-584f-8452-c9d8ce20610d', 'individual', 'Liam Nguyen', '2026-09-25 13:09:30.788267+00', '2026-09-25 13:09:30.788267+00', '834dc56d-7ac9-4c1a-bb47-4030aaecbebb');
INSERT INTO public.entity (id, entity_type, display_name, created_at, updated_at, financial_planner_id) VALUES ('8b0ef68e-dba1-57ee-9af3-50f7839669a4', 'individual', 'Ethan Brown', '2026-09-25 13:09:30.788267+00', '2026-09-25 13:09:30.788267+00', '834dc56d-7ac9-4c1a-bb47-4030aaecbebb');
INSERT INTO public.entity (id, entity_type, display_name, created_at, updated_at, financial_planner_id) VALUES ('1a2b7fd2-5f8f-5d8c-baf3-0e2ecf017997', 'individual', 'Ella Hassan', '2026-09-25 13:09:30.788267+00', '2026-09-25 13:09:30.788267+00', '834dc56d-7ac9-4c1a-bb47-4030aaecbebb');
INSERT INTO public.entity (id, entity_type, display_name, created_at, updated_at, financial_planner_id) VALUES ('b15a9373-b775-5211-afbf-1bceea904a95', 'individual', 'Grace Chen', '2026-09-25 13:09:30.788267+00', '2026-09-25 13:09:30.788267+00', '834dc56d-7ac9-4c1a-bb47-4030aaecbebb');
INSERT INTO public.entity (id, entity_type, display_name, created_at, updated_at, financial_planner_id) VALUES ('4472ba0b-7901-5e0e-af0a-812c347e574f', 'individual', 'Maya Nguyen', '2026-09-25 13:09:30.788267+00', '2026-09-25 13:09:30.788267+00', '834dc56d-7ac9-4c1a-bb47-4030aaecbebb');
INSERT INTO public.entity (id, entity_type, display_name, created_at, updated_at, financial_planner_id) VALUES ('a97799ee-e702-5031-ad8f-b80d762cec5a', 'individual', 'Owen Chen', '2026-09-25 13:09:30.788267+00', '2026-09-25 13:09:30.788267+00', '834dc56d-7ac9-4c1a-bb47-4030aaecbebb');
INSERT INTO public.entity (id, entity_type, display_name, created_at, updated_at, financial_planner_id) VALUES ('4a692464-d076-5c32-b162-63dcff4268f8', 'individual', 'John Smith', '2026-09-25 13:09:30.788267+00', '2026-09-25 13:09:30.788267+00', NULL);
INSERT INTO public.entity (id, entity_type, display_name, created_at, updated_at, financial_planner_id) VALUES ('f5c5e9a6-2d1c-5e46-b2a1-46e684e46995', 'individual', 'Jane Smith', '2026-09-25 13:09:30.788267+00', '2026-09-25 13:09:30.788267+00', NULL);
INSERT INTO public.entity (id, entity_type, display_name, created_at, updated_at, financial_planner_id) VALUES ('c4406eb7-c031-5f29-ab93-beea11e18887', 'individual', 'Michael Brown', '2026-09-25 13:09:30.788267+00', '2026-09-25 13:09:30.788267+00', NULL);
INSERT INTO public.entity (id, entity_type, display_name, created_at, updated_at, financial_planner_id) VALUES ('21340348-85a1-c72f-bdf1-0860c21d4b54', 'individual', 'Amelia Hartley', '2026-09-26 09:26:41.563295+00', '2026-09-29 15:45:54.624575+00', 'dfa5a8f7-56c8-97d2-dcf0-39c2da5b0d1d');
INSERT INTO public.entity (id, entity_type, display_name, created_at, updated_at, financial_planner_id) VALUES ('928618c6-fbe9-cefb-b909-8749139aba74', 'individual', 'Daniel Hartley', '2026-09-26 09:26:41.563295+00', '2026-09-29 15:45:54.624575+00', 'dfa5a8f7-56c8-97d2-dcf0-39c2da5b0d1d');
INSERT INTO public.entity (id, entity_type, display_name, created_at, updated_at, financial_planner_id) VALUES ('5876e49c-a05e-e482-b1c4-109d4f0d768f', 'individual', 'Priya Nair', '2026-09-26 09:26:41.563295+00', '2026-09-29 15:45:54.624575+00', '4017ffe1-b404-db14-18d1-e84fa4fde325');
INSERT INTO public.entity (id, entity_type, display_name, created_at, updated_at, financial_planner_id) VALUES ('ddbc9aa9-d048-17b2-5335-9682d9601396', 'individual', 'Lucas Bennett', '2026-09-26 09:26:41.563295+00', '2026-09-29 15:45:54.624575+00', '14701153-ca74-f338-6439-4bcefdef14aa');
INSERT INTO public.entity (id, entity_type, display_name, created_at, updated_at, financial_planner_id) VALUES ('e5a1a5da-551a-79fd-6753-e37c8f4df498', 'individual', 'Margaret Ellison', '2026-09-26 09:26:41.563295+00', '2026-09-29 15:45:54.624575+00', '84c2d8a4-cce1-a3c0-981c-92092ece7572');
INSERT INTO public.entity (id, entity_type, display_name, created_at, updated_at, financial_planner_id) VALUES ('24b01170-25fe-d82b-dfe4-1ec38494ac0f', 'individual', 'Ella Tran', '2026-09-26 09:26:41.563295+00', '2026-09-29 15:45:54.624575+00', '5e6c9ee8-3e7d-43ca-dbd6-75a41c90d78b');
INSERT INTO public.entity (id, entity_type, display_name, created_at, updated_at, financial_planner_id) VALUES ('89c9b482-62a4-4b1b-fadb-8947c86522b1', 'individual', 'Noah Mercer', '2026-09-26 09:26:41.563295+00', '2026-09-29 15:45:54.624575+00', '74f7b4ff-015c-602f-0992-eb94ae05723d');


--
-- Data for Name: entity_relationship; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.entity_relationship (id, from_entity_id, to_entity_id, relationship_type, created_at) VALUES ('952ae725-ae36-432f-a5d8-4239da0ac70b', '9528a13b-8bd4-4fc1-9db7-7214a931b13d', '4a692464-d076-5c32-b162-63dcff4268f8', 'Family Member', '2026-09-26 07:59:52.041107+00');
INSERT INTO public.entity_relationship (id, from_entity_id, to_entity_id, relationship_type, created_at) VALUES ('11c8b1fc-5d11-40ec-b8df-7b92b65eeab3', '9528a13b-8bd4-4fc1-9db7-7214a931b13d', 'f5c5e9a6-2d1c-5e46-b2a1-46e684e46995', 'Family Member', '2026-09-26 08:00:26.595864+00');
INSERT INTO public.entity_relationship (id, from_entity_id, to_entity_id, relationship_type, created_at) VALUES ('00b4b1e5-3244-81e6-e267-1d8f0f5e7467', '21340348-85a1-c72f-bdf1-0860c21d4b54', '928618c6-fbe9-cefb-b909-8749139aba74', 'Spouse', '2026-09-26 09:26:41.563295+00');
INSERT INTO public.entity_relationship (id, from_entity_id, to_entity_id, relationship_type, created_at) VALUES ('e636a994-edea-19bc-ec8a-3e4f1da185e0', '21340348-85a1-c72f-bdf1-0860c21d4b54', '3785316a-69e5-ad58-745e-ce8512001a71', 'Trustee', '2026-09-26 09:26:41.563295+00');
INSERT INTO public.entity_relationship (id, from_entity_id, to_entity_id, relationship_type, created_at) VALUES ('a29ce3cb-8af6-f468-ab2a-8c96e0362d0b', '928618c6-fbe9-cefb-b909-8749139aba74', 'ed645525-e3fb-adf1-f9f7-f91555fe272e', 'Director', '2026-09-26 09:26:41.563295+00');
INSERT INTO public.entity_relationship (id, from_entity_id, to_entity_id, relationship_type, created_at) VALUES ('1add57af-6acd-e178-405b-96c3ef2313ea', '21340348-85a1-c72f-bdf1-0860c21d4b54', '9707491d-65ca-c4c7-13d0-5b2bab871dc1', 'Joint owner', '2026-09-26 09:26:41.563295+00');
INSERT INTO public.entity_relationship (id, from_entity_id, to_entity_id, relationship_type, created_at) VALUES ('64c4fc6e-8f89-5ab7-0d51-b22c6fb58898', '928618c6-fbe9-cefb-b909-8749139aba74', '9707491d-65ca-c4c7-13d0-5b2bab871dc1', 'Joint owner', '2026-09-26 09:26:41.563295+00');


--
-- Data for Name: fact_find_beneficiary; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: fact_find_business_income; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_business_income (id, name, business_name, income_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('d331ba66-fb8b-595d-9ca7-ec04e15aeea1', 'Cafe profit distribution', 'Riverbend Cafe', 86000.00, true, 9000.00, 'New catering contract', NULL);
INSERT INTO public.fact_find_business_income (id, name, business_name, income_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('a7b6d288-f257-53c8-bf5e-111c30a2e3f3', 'Consulting profit', 'Northstar Design Studio', 58000.00, false, NULL, NULL, NULL);
INSERT INTO public.fact_find_business_income (id, name, business_name, income_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('bdddc66f-cdbe-5575-99f3-022f840b0983', 'Sole trader profit', 'Jack Trade Services', 74000.00, true, -6000.00, 'Reduced working days', NULL);
INSERT INTO public.fact_find_business_income (id, name, business_name, income_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('aac75691-6d4b-5c55-aa32-a612d27ef1c0', 'Business profit', 'Coastal Parts Distribution', 132000.00, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_business_income (id, name, business_name, income_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('c65ed713-2fef-6ad6-f5f2-3937e7587456', 'Hartley Design Studio distributions', NULL, 24000.00, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_business_income (id, name, business_name, income_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('25145379-b35b-4ea4-96b0-13fa3f54c01b', 'Hartley Design Studio distributions', NULL, 24000.00, NULL, NULL, NULL, '6e7ac885-bf77-40d9-bb9a-7a827827bf66');


--
-- Data for Name: fact_find_business_income_ownership; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_business_income_ownership (id, business_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('4acae0d8-93d3-5d41-b5ef-6b72f3425e32', 'd331ba66-fb8b-595d-9ca7-ec04e15aeea1', '4472ba0b-7901-5e0e-af0a-812c347e574f', 50.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_business_income_ownership (id, business_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('72c00771-060d-57e1-9786-103a02f1fefb', 'd331ba66-fb8b-595d-9ca7-ec04e15aeea1', 'd40656e0-fd5c-584f-8452-c9d8ce20610d', 50.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_business_income_ownership (id, business_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('4cac4296-e98a-54d3-87b0-d0b3917d36c4', 'a7b6d288-f257-53c8-bf5e-111c30a2e3f3', 'e2fb9ead-5c3d-5f07-9030-2eb109ea027b', 100.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_business_income_ownership (id, business_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('a3d8b619-18be-56bb-8548-b1ca420a0e61', 'bdddc66f-cdbe-5575-99f3-022f840b0983', '2fd1c862-d355-514c-a415-c30dd66168ef', 100.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_business_income_ownership (id, business_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('52070f53-fd30-5158-9946-016be58ec92e', 'aac75691-6d4b-5c55-aa32-a612d27ef1c0', '8b0ef68e-dba1-57ee-9af3-50f7839669a4', 60.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_business_income_ownership (id, business_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('6c2e5f28-f5e5-5d83-add0-dfee5f2fef31', 'aac75691-6d4b-5c55-aa32-a612d27ef1c0', 'ea87fa5d-abe4-5a46-b31e-d036cc2abc8a', 40.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_business_income_ownership (id, business_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('9216dd5a-58e8-242d-0a22-b88347ca2a36', 'c65ed713-2fef-6ad6-f5f2-3937e7587456', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00');
INSERT INTO public.fact_find_business_income_ownership (id, business_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('a857ab86-1c46-4dfe-b2eb-d8c5256608dd', '25145379-b35b-4ea4-96b0-13fa3f54c01b', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00, '2026-10-06 08:03:27.459339+00', '2026-10-06 08:03:27.459638+00');


--
-- Data for Name: fact_find_cash; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: fact_find_cash_ownership; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: fact_find_centrelink_income; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_centrelink_income (id, name, income_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('6cf2b357-8c5e-5e68-b69c-90267aa0c789', 'Age Pension', 18500.00, false, NULL, NULL, NULL);
INSERT INTO public.fact_find_centrelink_income (id, name, income_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('64db40e4-3163-5e18-b4d8-523d13f03416', 'Age Pension', 16800.00, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_centrelink_income (id, name, income_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('96bb8483-132a-5d7d-a2dc-5c46483968ee', 'Age Pension', 24100.00, true, 1100.00, 'Payment review', NULL);
INSERT INTO public.fact_find_centrelink_income (id, name, income_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('61190c3b-e693-7fa9-0313-ea63b46a5928', 'Part age pension', 6200.00, NULL, NULL, NULL, NULL);


--
-- Data for Name: fact_find_centrelink_income_ownership; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_centrelink_income_ownership (id, centrelink_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('ca6a0be0-2915-5766-8e4c-f83b5204309f', '6cf2b357-8c5e-5e68-b69c-90267aa0c789', 'b15a9373-b775-5211-afbf-1bceea904a95', 100.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_centrelink_income_ownership (id, centrelink_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('79362bb1-8d6e-5602-8271-666bca4884c8', '64db40e4-3163-5e18-b4d8-523d13f03416', 'a97799ee-e702-5031-ad8f-b80d762cec5a', 100.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_centrelink_income_ownership (id, centrelink_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('602d46d7-ee8e-5a7b-82f0-dc2778e2ad66', '96bb8483-132a-5d7d-a2dc-5c46483968ee', 'f9438f7c-a8e5-5839-8673-057ba714d3a0', 100.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_centrelink_income_ownership (id, centrelink_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('da0e95bc-e472-8f89-354c-6668a8a4798c', '61190c3b-e693-7fa9-0313-ea63b46a5928', 'e5a1a5da-551a-79fd-6753-e37c8f4df498', 100.00, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00');


--
-- Data for Name: fact_find_credit_card; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_credit_card (id, name, provider, product_name, card_type, establishment_date, credit_limit, current_balance, current_interest_rate, interest_free_period, minimum_monthly_repayment, current_monthly_repayment, annual_account_fee, monthly_fee, balance_transfer_fee_amount, balance_transfer_fee_percent, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('d5a58315-34d2-554a-bb48-673416bf4e34', 'Everyday Visa', 'ANZ', 'Rewards Platinum', 'Visa', '2021-04-10', 15000.00, 3200.00, 20.9900, '55 days', 90.00, 1000.00, 295.00, NULL, NULL, NULL, NULL, NULL, NULL, '70f35aaa-57fd-4d14-9ce3-269bf7192c32');
INSERT INTO public.fact_find_credit_card (id, name, provider, product_name, card_type, establishment_date, credit_limit, current_balance, current_interest_rate, interest_free_period, minimum_monthly_repayment, current_monthly_repayment, annual_account_fee, monthly_fee, balance_transfer_fee_amount, balance_transfer_fee_percent, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('880c1cdd-5a52-4a08-a0fb-3e231d81b644', 'Credit Card', 'ANZ BANK', 'Credit Card', 'Platnium', '2026-09-12', 12000.00, 6000.00, 12.0000, '30', 1000.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'a9118796-df4b-4930-a991-a3fdc5a7a2f6');
INSERT INTO public.fact_find_credit_card (id, name, provider, product_name, card_type, establishment_date, credit_limit, current_balance, current_interest_rate, interest_free_period, minimum_monthly_repayment, current_monthly_repayment, annual_account_fee, monthly_fee, balance_transfer_fee_amount, balance_transfer_fee_percent, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('226e3d45-c6b4-130f-d514-6f74cd3ecf7e', 'Household credit card', NULL, NULL, NULL, NULL, NULL, 2800.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b6f144d8-64bd-83a9-2770-b5bd7162f031');
INSERT INTO public.fact_find_credit_card (id, name, provider, product_name, card_type, establishment_date, credit_limit, current_balance, current_interest_rate, interest_free_period, minimum_monthly_repayment, current_monthly_repayment, annual_account_fee, monthly_fee, balance_transfer_fee_amount, balance_transfer_fee_percent, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('c5403c2a-fe67-6739-6cb5-c46a7cddb035', 'Everyday credit card', NULL, NULL, NULL, NULL, NULL, 9200.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b6f144d8-64bd-83a9-2770-b5bd7162f031');
INSERT INTO public.fact_find_credit_card (id, name, provider, product_name, card_type, establishment_date, credit_limit, current_balance, current_interest_rate, interest_free_period, minimum_monthly_repayment, current_monthly_repayment, annual_account_fee, monthly_fee, balance_transfer_fee_amount, balance_transfer_fee_percent, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('b579ab72-3722-d541-05a0-5a72777ea4dd', 'Travel credit card', NULL, NULL, NULL, NULL, NULL, 4600.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'f51e3db9-fb17-9dba-6213-590dec43a8db');
INSERT INTO public.fact_find_credit_card (id, name, provider, product_name, card_type, establishment_date, credit_limit, current_balance, current_interest_rate, interest_free_period, minimum_monthly_repayment, current_monthly_repayment, annual_account_fee, monthly_fee, balance_transfer_fee_amount, balance_transfer_fee_percent, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('d1002d4c-4653-43b7-a8f6-356d30ba8140', 'Credit Card', 'ANZ BANK', 'Credit Card', 'Platnium', '2026-09-12', 12000.00, 6000.00, 12.0000, '30', 1000.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '6e7ac885-bf77-40d9-bb9a-7a827827bf66', 'a9118796-df4b-4930-a991-a3fdc5a7a2f6');
INSERT INTO public.fact_find_credit_card (id, name, provider, product_name, card_type, establishment_date, credit_limit, current_balance, current_interest_rate, interest_free_period, minimum_monthly_repayment, current_monthly_repayment, annual_account_fee, monthly_fee, balance_transfer_fee_amount, balance_transfer_fee_percent, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('688f31dd-e281-46a4-8e2c-ff1086927ae1', 'Household credit card', NULL, NULL, NULL, NULL, NULL, 2800.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '6e7ac885-bf77-40d9-bb9a-7a827827bf66', 'b6f144d8-64bd-83a9-2770-b5bd7162f031');


--
-- Data for Name: fact_find_credit_card_ownership; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_credit_card_ownership (id, credit_card_id, entity_id, ownership_percentage) VALUES ('64d908c4-0bb1-5f3c-9962-0db90d01e484', 'd5a58315-34d2-554a-bb48-673416bf4e34', '4a692464-d076-5c32-b162-63dcff4268f8', 100.00);
INSERT INTO public.fact_find_credit_card_ownership (id, credit_card_id, entity_id, ownership_percentage) VALUES ('a773218a-10be-4b70-b9fc-e76b919261e5', '880c1cdd-5a52-4a08-a0fb-3e231d81b644', '0214f9b3-de82-52b5-b213-b825b2dfdf7c', 100.00);
INSERT INTO public.fact_find_credit_card_ownership (id, credit_card_id, entity_id, ownership_percentage) VALUES ('48ca7322-1ede-4ac8-bb28-206ef4f3b8c4', '226e3d45-c6b4-130f-d514-6f74cd3ecf7e', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);
INSERT INTO public.fact_find_credit_card_ownership (id, credit_card_id, entity_id, ownership_percentage) VALUES ('a1a8e48b-7b26-4336-836e-25f3ae8953da', 'c5403c2a-fe67-6739-6cb5-c46a7cddb035', 'ddbc9aa9-d048-17b2-5335-9682d9601396', 100.00);
INSERT INTO public.fact_find_credit_card_ownership (id, credit_card_id, entity_id, ownership_percentage) VALUES ('b748d3ba-0d17-98fd-efbd-aab361cbb798', 'b579ab72-3722-d541-05a0-5a72777ea4dd', 'ddbc9aa9-d048-17b2-5335-9682d9601396', 100.00);
INSERT INTO public.fact_find_credit_card_ownership (id, credit_card_id, entity_id, ownership_percentage) VALUES ('d0716901-d3be-40b6-9390-d281fd6d5cb5', 'd1002d4c-4653-43b7-a8f6-356d30ba8140', '0214f9b3-de82-52b5-b213-b825b2dfdf7c', 100.00);
INSERT INTO public.fact_find_credit_card_ownership (id, credit_card_id, entity_id, ownership_percentage) VALUES ('58bc8772-6b59-4276-86de-cb21014281cb', '688f31dd-e281-46a4-8e2c-ff1086927ae1', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);


--
-- Data for Name: fact_find_direct_investment; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_direct_investment (id, name, provider_name, product_name, account_number, account_established_date, investment_purchase_date, purchase_price, quantity_purchased, opening_balance, account_balance, current_value, administration_fee_amount, administration_fee_percent, adviser_fee_amount, adviser_fee_percent, management_fee_percent, asset_fee_amount, asset_fee_percent, contribution_fee_amount, contribution_fee_percent, exit_withdrawal_fee_amount, exit_withdrawal_fee_percent, brokerage_buy_fee_amount, brokerage_buy_fee_percent, brokerage_sell_fee_amount, brokerage_sell_fee_percent, switch_fee_amount, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('ba2303b4-1cdb-5c1c-8a7e-85a6ecbc5f66', 'Australian shares portfolio', 'CommSec', 'Direct Shares', 'CS-88421', '2018-03-01', '2018-03-01', 90000.00, 1.000000, NULL, 168000.00, 168000.00, 0.00, NULL, 0.00, NULL, 0.0000, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '5851d76e-e74e-4065-b12f-1b70060cf247');
INSERT INTO public.fact_find_direct_investment (id, name, provider_name, product_name, account_number, account_established_date, investment_purchase_date, purchase_price, quantity_purchased, opening_balance, account_balance, current_value, administration_fee_amount, administration_fee_percent, adviser_fee_amount, adviser_fee_percent, management_fee_percent, asset_fee_amount, asset_fee_percent, contribution_fee_amount, contribution_fee_percent, exit_withdrawal_fee_amount, exit_withdrawal_fee_percent, brokerage_buy_fee_amount, brokerage_buy_fee_percent, brokerage_sell_fee_amount, brokerage_sell_fee_percent, switch_fee_amount, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('4698d437-a0ed-a62f-1022-b2b44a17dc67', 'Long-term equity portfolio', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 96000.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '717fe799-f5ac-2dd7-58eb-76e1e03182c7');
INSERT INTO public.fact_find_direct_investment (id, name, provider_name, product_name, account_number, account_established_date, investment_purchase_date, purchase_price, quantity_purchased, opening_balance, account_balance, current_value, administration_fee_amount, administration_fee_percent, adviser_fee_amount, adviser_fee_percent, management_fee_percent, asset_fee_amount, asset_fee_percent, contribution_fee_amount, contribution_fee_percent, exit_withdrawal_fee_amount, exit_withdrawal_fee_percent, brokerage_buy_fee_amount, brokerage_buy_fee_percent, brokerage_sell_fee_amount, brokerage_sell_fee_percent, switch_fee_amount, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('a6189760-ea4b-d01b-301d-6581810e53a2', 'Global equity holdings', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 248000.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '8bc8398a-66f6-cf50-aabf-8b3123d197f9');
INSERT INTO public.fact_find_direct_investment (id, name, provider_name, product_name, account_number, account_established_date, investment_purchase_date, purchase_price, quantity_purchased, opening_balance, account_balance, current_value, administration_fee_amount, administration_fee_percent, adviser_fee_amount, adviser_fee_percent, management_fee_percent, asset_fee_amount, asset_fee_percent, contribution_fee_amount, contribution_fee_percent, exit_withdrawal_fee_amount, exit_withdrawal_fee_percent, brokerage_buy_fee_amount, brokerage_buy_fee_percent, brokerage_sell_fee_amount, brokerage_sell_fee_percent, switch_fee_amount, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('d2c315d3-ebf4-44d3-81e4-6447ca95e830', 'Long-term equity portfolio', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 96000.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '6e7ac885-bf77-40d9-bb9a-7a827827bf66', '717fe799-f5ac-2dd7-58eb-76e1e03182c7');


--
-- Data for Name: fact_find_direct_investment_item; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_direct_investment_item (id, direct_investment_id, name, product_name, quantity, unit_price, current_value, allocation_percentage, financial_product_id) VALUES ('d93367a0-488e-5929-9dc0-792d14b395cf', 'ba2303b4-1cdb-5c1c-8a7e-85a6ecbc5f66', 'BHP Group', 'BHP', 1500.000000, 44.000000, 66000.00, 39.2900, NULL);
INSERT INTO public.fact_find_direct_investment_item (id, direct_investment_id, name, product_name, quantity, unit_price, current_value, allocation_percentage, financial_product_id) VALUES ('8be6f974-d86a-5841-9cd0-247f65d3ca4b', 'ba2303b4-1cdb-5c1c-8a7e-85a6ecbc5f66', 'Commonwealth Bank', 'CBA', 600.000000, 170.000000, 102000.00, 60.7100, NULL);
INSERT INTO public.fact_find_direct_investment_item (id, direct_investment_id, name, product_name, quantity, unit_price, current_value, allocation_percentage, financial_product_id) VALUES ('81978ada-546a-6a06-2dff-8356e7f21fee', '4698d437-a0ed-a62f-1022-b2b44a17dc67', 'Australian Equity Index', NULL, NULL, NULL, 57600.00, 60.0000, '9fd2e96c-2fff-7e85-cee9-3b62a2c78d2b');
INSERT INTO public.fact_find_direct_investment_item (id, direct_investment_id, name, product_name, quantity, unit_price, current_value, allocation_percentage, financial_product_id) VALUES ('fd5424dc-5608-503e-6c6a-faa0b8c5b78f', '4698d437-a0ed-a62f-1022-b2b44a17dc67', 'Ordinary Shares', NULL, NULL, NULL, 38400.00, 40.0000, 'f116d744-f26b-2619-8ce0-51144c12c4d4');
INSERT INTO public.fact_find_direct_investment_item (id, direct_investment_id, name, product_name, quantity, unit_price, current_value, allocation_percentage, financial_product_id) VALUES ('27685fa6-0aad-4922-b984-d61f5b90f87d', 'd2c315d3-ebf4-44d3-81e4-6447ca95e830', 'Australian Equity Index', NULL, NULL, NULL, 57600.00, 60.0000, '9fd2e96c-2fff-7e85-cee9-3b62a2c78d2b');
INSERT INTO public.fact_find_direct_investment_item (id, direct_investment_id, name, product_name, quantity, unit_price, current_value, allocation_percentage, financial_product_id) VALUES ('51457111-fb8b-45e8-bdc5-1a8c45fdf1eb', 'd2c315d3-ebf4-44d3-81e4-6447ca95e830', 'Ordinary Shares', NULL, NULL, NULL, 38400.00, 40.0000, 'f116d744-f26b-2619-8ce0-51144c12c4d4');


--
-- Data for Name: fact_find_direct_investment_ownership; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_direct_investment_ownership (id, direct_investment_id, entity_id, ownership_percentage) VALUES ('19ce8e95-4451-5f28-a847-abe3b068d013', 'ba2303b4-1cdb-5c1c-8a7e-85a6ecbc5f66', '4a692464-d076-5c32-b162-63dcff4268f8', 100.00);
INSERT INTO public.fact_find_direct_investment_ownership (id, direct_investment_id, entity_id, ownership_percentage) VALUES ('e2a54d1b-f2a9-6e55-74bb-c6dd73c60f31', '4698d437-a0ed-a62f-1022-b2b44a17dc67', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);
INSERT INTO public.fact_find_direct_investment_ownership (id, direct_investment_id, entity_id, ownership_percentage) VALUES ('eb6f7b03-9a85-5601-7cd4-93c3c2b0c090', 'a6189760-ea4b-d01b-301d-6581810e53a2', '5876e49c-a05e-e482-b1c4-109d4f0d768f', 100.00);
INSERT INTO public.fact_find_direct_investment_ownership (id, direct_investment_id, entity_id, ownership_percentage) VALUES ('3cf9fe42-b0b2-4292-ae74-f41fd3299bf6', 'd2c315d3-ebf4-44d3-81e4-6447ca95e830', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);


--
-- Data for Name: fact_find_expense; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_expense (id, name, category, subcategory, amount, frequency, other_expense_description, expected_to_change, change_amount, change_reason, case_id) VALUES ('b63e4f31-3b95-5e1e-aaf2-6f137551f1bb', 'Household living costs', 'Living expenses', 'General', 42000.00, 'annual', NULL, false, NULL, NULL, NULL);
INSERT INTO public.fact_find_expense (id, name, category, subcategory, amount, frequency, other_expense_description, expected_to_change, change_amount, change_reason, case_id) VALUES ('a7e9166d-080a-5ac0-af0c-bc9b97a470d0', 'Private school fees', 'Education', 'School fees', 18000.00, 'annual', NULL, true, 1500.00, 'Expected fee increase', NULL);
INSERT INTO public.fact_find_expense (id, name, category, subcategory, amount, frequency, other_expense_description, expected_to_change, change_amount, change_reason, case_id) VALUES ('7f5ca528-072c-574f-be14-4a5733efc5fb', 'General insurance', 'Insurance', 'Home and motor', 5200.00, 'annual', NULL, false, NULL, NULL, NULL);
INSERT INTO public.fact_find_expense (id, name, category, subcategory, amount, frequency, other_expense_description, expected_to_change, change_amount, change_reason, case_id) VALUES ('c08dbca4-f4be-49c3-8b6b-e012d5d185bb', 'Rent', 'Rent', 'Rent', 300.00, 'Weekly', NULL, false, NULL, NULL, NULL);
INSERT INTO public.fact_find_expense (id, name, category, subcategory, amount, frequency, other_expense_description, expected_to_change, change_amount, change_reason, case_id) VALUES ('746f97f7-b780-93c8-41bc-0b4df62bcac6', 'Groceries and household supplies', 'Living', NULL, 1400.00, 'monthly', NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_expense (id, name, category, subcategory, amount, frequency, other_expense_description, expected_to_change, change_amount, change_reason, case_id) VALUES ('562b6f40-6c3d-3fe5-2979-346bea83bac1', 'Electricity, water and internet', 'Utilities', NULL, 420.00, 'monthly', NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_expense (id, name, category, subcategory, amount, frequency, other_expense_description, expected_to_change, change_amount, change_reason, case_id) VALUES ('c087838f-594b-2938-14c8-82afc1965e87', 'School fees and activities', 'Education', NULL, 18000.00, 'annual', NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_expense (id, name, category, subcategory, amount, frequency, other_expense_description, expected_to_change, change_amount, change_reason, case_id) VALUES ('ec15361a-b0f8-89e9-15ef-0efb53c66bfd', 'Family holiday budget', 'Lifestyle', NULL, 9000.00, 'annual', NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_expense (id, name, category, subcategory, amount, frequency, other_expense_description, expected_to_change, change_amount, change_reason, case_id) VALUES ('9e444704-9a20-874b-2f8b-fbbf423d7890', 'Fuel and public transport', 'Transport', NULL, 120.00, 'weekly', NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_expense (id, name, category, subcategory, amount, frequency, other_expense_description, expected_to_change, change_amount, change_reason, case_id) VALUES ('e31cdffc-8582-c120-55e6-4ac9ecc2ad24', 'Apartment rent', 'Housing', NULL, 580.00, 'weekly', NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_expense (id, name, category, subcategory, amount, frequency, other_expense_description, expected_to_change, change_amount, change_reason, case_id) VALUES ('20a7eac6-6a33-4c8a-850f-b44b1037e9d3', 'Rent', 'Rent', 'Rent', 300.00, 'Weekly', NULL, false, NULL, NULL, '6e7ac885-bf77-40d9-bb9a-7a827827bf66');
INSERT INTO public.fact_find_expense (id, name, category, subcategory, amount, frequency, other_expense_description, expected_to_change, change_amount, change_reason, case_id) VALUES ('cbb8f3be-bcb7-40a9-b96d-3c9e9f73f4a2', 'Groceries and household supplies', 'Living', NULL, 1400.00, 'monthly', NULL, NULL, NULL, NULL, '6e7ac885-bf77-40d9-bb9a-7a827827bf66');
INSERT INTO public.fact_find_expense (id, name, category, subcategory, amount, frequency, other_expense_description, expected_to_change, change_amount, change_reason, case_id) VALUES ('3ac5392d-2517-4c13-b97a-efc2aa709e19', 'Electricity, water and internet', 'Utilities', NULL, 420.00, 'monthly', NULL, NULL, NULL, NULL, '6e7ac885-bf77-40d9-bb9a-7a827827bf66');
INSERT INTO public.fact_find_expense (id, name, category, subcategory, amount, frequency, other_expense_description, expected_to_change, change_amount, change_reason, case_id) VALUES ('c9fdf4a5-e7b6-466b-a625-27870c644ed5', 'School fees and activities', 'Education', NULL, 18000.00, 'annual', NULL, NULL, NULL, NULL, '6e7ac885-bf77-40d9-bb9a-7a827827bf66');
INSERT INTO public.fact_find_expense (id, name, category, subcategory, amount, frequency, other_expense_description, expected_to_change, change_amount, change_reason, case_id) VALUES ('8de1bbd8-dd28-47ea-b315-76e4b33b10ec', 'Family holiday budget', 'Lifestyle', NULL, 9000.00, 'annual', NULL, NULL, NULL, NULL, '6e7ac885-bf77-40d9-bb9a-7a827827bf66');
INSERT INTO public.fact_find_expense (id, name, category, subcategory, amount, frequency, other_expense_description, expected_to_change, change_amount, change_reason, case_id) VALUES ('4a2d785d-0873-4ec6-99e5-9058b6738922', 'Fuel and public transport', 'Transport', NULL, 120.00, 'weekly', NULL, NULL, NULL, NULL, '6e7ac885-bf77-40d9-bb9a-7a827827bf66');


--
-- Data for Name: fact_find_expense_ownership; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_expense_ownership (id, expense_id, entity_id, ownership_percentage) VALUES ('e79e24a6-a9f9-5cbf-9848-d1fd906d8774', 'b63e4f31-3b95-5e1e-aaf2-6f137551f1bb', '4a692464-d076-5c32-b162-63dcff4268f8', 50.00);
INSERT INTO public.fact_find_expense_ownership (id, expense_id, entity_id, ownership_percentage) VALUES ('243b83ef-018d-5e7c-9ab5-27ec7a397a03', 'b63e4f31-3b95-5e1e-aaf2-6f137551f1bb', 'f5c5e9a6-2d1c-5e46-b2a1-46e684e46995', 50.00);
INSERT INTO public.fact_find_expense_ownership (id, expense_id, entity_id, ownership_percentage) VALUES ('17085db7-8283-5397-96bb-3e7ca5a07829', 'a7e9166d-080a-5ac0-af0c-bc9b97a470d0', '4a692464-d076-5c32-b162-63dcff4268f8', 50.00);
INSERT INTO public.fact_find_expense_ownership (id, expense_id, entity_id, ownership_percentage) VALUES ('e1cf2f6c-7ab2-5949-9213-be5183bf20c5', 'a7e9166d-080a-5ac0-af0c-bc9b97a470d0', 'f5c5e9a6-2d1c-5e46-b2a1-46e684e46995', 50.00);
INSERT INTO public.fact_find_expense_ownership (id, expense_id, entity_id, ownership_percentage) VALUES ('a008dccb-53da-578e-96a0-013ff347435c', '7f5ca528-072c-574f-be14-4a5733efc5fb', '4a692464-d076-5c32-b162-63dcff4268f8', 50.00);
INSERT INTO public.fact_find_expense_ownership (id, expense_id, entity_id, ownership_percentage) VALUES ('2ad6fb23-bb0c-541f-a09c-56afe66fdb42', '7f5ca528-072c-574f-be14-4a5733efc5fb', 'f5c5e9a6-2d1c-5e46-b2a1-46e684e46995', 50.00);
INSERT INTO public.fact_find_expense_ownership (id, expense_id, entity_id, ownership_percentage) VALUES ('0707a781-572c-48f8-9c5c-696ad30c5be1', 'c08dbca4-f4be-49c3-8b6b-e012d5d185bb', '0214f9b3-de82-52b5-b213-b825b2dfdf7c', 100.00);
INSERT INTO public.fact_find_expense_ownership (id, expense_id, entity_id, ownership_percentage) VALUES ('de343b35-3c45-2dea-65bd-227809472710', '746f97f7-b780-93c8-41bc-0b4df62bcac6', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);
INSERT INTO public.fact_find_expense_ownership (id, expense_id, entity_id, ownership_percentage) VALUES ('0dd7b504-050f-d8f3-da00-59dbc25c4c09', '562b6f40-6c3d-3fe5-2979-346bea83bac1', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);
INSERT INTO public.fact_find_expense_ownership (id, expense_id, entity_id, ownership_percentage) VALUES ('aa060f2a-af22-3628-f54d-76ce69fe9ba2', 'c087838f-594b-2938-14c8-82afc1965e87', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);
INSERT INTO public.fact_find_expense_ownership (id, expense_id, entity_id, ownership_percentage) VALUES ('32fc3bb9-2cf8-2e7c-0e08-75b9073a8f8b', 'ec15361a-b0f8-89e9-15ef-0efb53c66bfd', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);
INSERT INTO public.fact_find_expense_ownership (id, expense_id, entity_id, ownership_percentage) VALUES ('8fe963e5-ad33-5ecb-4212-fcc8ca0014f9', '9e444704-9a20-874b-2f8b-fbbf423d7890', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);
INSERT INTO public.fact_find_expense_ownership (id, expense_id, entity_id, ownership_percentage) VALUES ('8b38b5e5-19e0-b0fd-5543-4ebf91b19432', 'e31cdffc-8582-c120-55e6-4ac9ecc2ad24', 'ddbc9aa9-d048-17b2-5335-9682d9601396', 100.00);
INSERT INTO public.fact_find_expense_ownership (id, expense_id, entity_id, ownership_percentage) VALUES ('011cfdb1-8eda-4e2f-ae9d-5274d2ae73af', '20a7eac6-6a33-4c8a-850f-b44b1037e9d3', '0214f9b3-de82-52b5-b213-b825b2dfdf7c', 100.00);
INSERT INTO public.fact_find_expense_ownership (id, expense_id, entity_id, ownership_percentage) VALUES ('fb142e60-85e2-416a-995b-0b2a10d87e95', 'cbb8f3be-bcb7-40a9-b96d-3c9e9f73f4a2', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);
INSERT INTO public.fact_find_expense_ownership (id, expense_id, entity_id, ownership_percentage) VALUES ('f65c70e1-dd50-414a-8f33-0d05f9a979d5', '3ac5392d-2517-4c13-b97a-efc2aa709e19', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);
INSERT INTO public.fact_find_expense_ownership (id, expense_id, entity_id, ownership_percentage) VALUES ('d0201ea4-c553-463e-abd3-22227ad3453f', 'c9fdf4a5-e7b6-466b-a625-27870c644ed5', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);
INSERT INTO public.fact_find_expense_ownership (id, expense_id, entity_id, ownership_percentage) VALUES ('add64337-4930-4dc5-899c-e8a95838b0cd', '8de1bbd8-dd28-47ea-b315-76e4b33b10ec', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);
INSERT INTO public.fact_find_expense_ownership (id, expense_id, entity_id, ownership_percentage) VALUES ('ce97efb5-6603-49f3-8f9f-2eda4ead0700', '4a2d785d-0873-4ec6-99e5-9058b6738922', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);


--
-- Data for Name: fact_find_fixed_interest; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_fixed_interest (id, name, provider, product_name, account_number, investment_type, start_date, maturity_date, balance, interest_rate, interest_frequency, account_fee, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('2762e178-b8eb-5489-b7f8-2b6eb952f500', '12 month term deposit', 'ING', 'Term Deposit', 'TD-48120', 'Term deposit', '2026-07-01', '2027-07-01', 50000.00, 4.5500, 'At maturity', NULL, NULL, NULL, NULL, 'be1681ce-e260-471a-bdfd-41a484599c29');
INSERT INTO public.fact_find_fixed_interest (id, name, provider, product_name, account_number, investment_type, start_date, maturity_date, balance, interest_rate, interest_frequency, account_fee, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('1d09c145-fc38-91ec-c072-cc656ef5098d', 'School fee reserve', NULL, NULL, NULL, NULL, NULL, NULL, 35000.00, 4.1000, NULL, NULL, NULL, NULL, NULL, '9fab45a3-71ae-9dca-fd04-9cf1e0ebe046');
INSERT INTO public.fact_find_fixed_interest (id, name, provider, product_name, account_number, investment_type, start_date, maturity_date, balance, interest_rate, interest_frequency, account_fee, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('7d98bf52-e499-92ab-a158-e2d9f422bb6d', 'Retirement cash ladder', NULL, NULL, NULL, NULL, NULL, NULL, 65000.00, NULL, NULL, NULL, NULL, NULL, NULL, 'e0add750-7688-8bc2-f47e-8f390b0a70a8');
INSERT INTO public.fact_find_fixed_interest (id, name, provider, product_name, account_number, investment_type, start_date, maturity_date, balance, interest_rate, interest_frequency, account_fee, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('377a4bf8-c289-478f-89d9-a30930cd8b95', 'School fee reserve', NULL, NULL, NULL, NULL, NULL, NULL, 35000.00, 4.1000, NULL, NULL, NULL, NULL, '6e7ac885-bf77-40d9-bb9a-7a827827bf66', '9fab45a3-71ae-9dca-fd04-9cf1e0ebe046');


--
-- Data for Name: fact_find_fixed_interest_ownership; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_fixed_interest_ownership (id, fixed_interest_id, entity_id, ownership_percentage) VALUES ('0a760086-fbca-559a-a266-ce59423d7236', '2762e178-b8eb-5489-b7f8-2b6eb952f500', '4a692464-d076-5c32-b162-63dcff4268f8', 100.00);
INSERT INTO public.fact_find_fixed_interest_ownership (id, fixed_interest_id, entity_id, ownership_percentage) VALUES ('5a5eece0-1da8-70a3-2f99-5e0de4ac7544', '1d09c145-fc38-91ec-c072-cc656ef5098d', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);
INSERT INTO public.fact_find_fixed_interest_ownership (id, fixed_interest_id, entity_id, ownership_percentage) VALUES ('61cb266c-af2c-d807-96d3-9347b42e7da9', '7d98bf52-e499-92ab-a158-e2d9f422bb6d', 'e5a1a5da-551a-79fd-6753-e37c8f4df498', 100.00);
INSERT INTO public.fact_find_fixed_interest_ownership (id, fixed_interest_id, entity_id, ownership_percentage) VALUES ('ff3b8962-643c-46fb-8b82-93e517fde6ab', '377a4bf8-c289-478f-89d9-a30930cd8b95', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);


--
-- Data for Name: fact_find_foreign_income; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_foreign_income (id, name, income_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('e22d5bf1-3e3d-5e67-a849-fc70cbee3386', 'UK share dividends', 7400.00, true, 400.00, 'Dividend increase', NULL);
INSERT INTO public.fact_find_foreign_income (id, name, income_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('4f6c2b46-d6cd-540d-a436-b7ffcaf7cf6b', 'Overseas consulting', 22000.00, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_foreign_income (id, name, income_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('57bfbc27-4d39-5d16-b6ea-6e066897151e', 'Foreign bank interest', 2200.00, false, NULL, NULL, NULL);
INSERT INTO public.fact_find_foreign_income (id, name, income_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('6e623972-0215-7725-9357-60ee1ec33468', 'Overseas equity distributions (AUD)', 1800.00, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_foreign_income (id, name, income_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('e14a6d9d-013b-43dd-af7e-4ed0ac0c9cff', 'UK share dividends', 7400.00, true, 400.00, 'Dividend increase', '6e7ac885-bf77-40d9-bb9a-7a827827bf66');
INSERT INTO public.fact_find_foreign_income (id, name, income_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('a895d11e-886e-49ba-aafa-b667c9d3bd9d', 'Overseas equity distributions (AUD)', 1800.00, NULL, NULL, NULL, '6e7ac885-bf77-40d9-bb9a-7a827827bf66');


--
-- Data for Name: fact_find_foreign_income_ownership; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_foreign_income_ownership (id, foreign_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('cf389dca-a3f2-5978-9645-99cf3c7481fb', 'e22d5bf1-3e3d-5e67-a849-fc70cbee3386', '0214f9b3-de82-52b5-b213-b825b2dfdf7c', 100.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_foreign_income_ownership (id, foreign_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('86d1ea76-963c-5dbe-b538-f5364cc692fa', '4f6c2b46-d6cd-540d-a436-b7ffcaf7cf6b', 'aff315ca-e674-5e50-8a58-b4b697c78301', 100.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_foreign_income_ownership (id, foreign_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('e18c3a23-c272-5dc0-8945-ffee0ec1d2c2', '57bfbc27-4d39-5d16-b6ea-6e066897151e', 'ea87fa5d-abe4-5a46-b31e-d036cc2abc8a', 100.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_foreign_income_ownership (id, foreign_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('047614f5-2fa5-9b94-135c-62c17ff08932', '6e623972-0215-7725-9357-60ee1ec33468', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00');
INSERT INTO public.fact_find_foreign_income_ownership (id, foreign_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('5cdefae5-40a9-4b87-ad36-39e4202487a0', 'e14a6d9d-013b-43dd-af7e-4ed0ac0c9cff', '0214f9b3-de82-52b5-b213-b825b2dfdf7c', 100.00, '2026-10-06 08:03:27.483596+00', '2026-10-06 08:03:27.483597+00');
INSERT INTO public.fact_find_foreign_income_ownership (id, foreign_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('a9797e1a-4196-4ef0-aba7-e32e93aff195', 'a895d11e-886e-49ba-aafa-b667c9d3bd9d', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00, '2026-10-06 08:03:27.485096+00', '2026-10-06 08:03:27.485098+00');


--
-- Data for Name: fact_find_home_contents; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_home_contents (id, name, value, case_id) VALUES ('482d4ffd-8015-52c8-99bb-0df3e53daded', 'Household contents', 95000.00, NULL);
INSERT INTO public.fact_find_home_contents (id, name, value, case_id) VALUES ('94605cd3-88e8-fdc6-520b-ca792aa9c15a', 'Household contents', 85000.00, NULL);
INSERT INTO public.fact_find_home_contents (id, name, value, case_id) VALUES ('44ffca82-e941-4a31-8f05-92b0a8b840d1', 'Household contents', 85000.00, '6e7ac885-bf77-40d9-bb9a-7a827827bf66');


--
-- Data for Name: fact_find_home_contents_ownership; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_home_contents_ownership (id, home_contents_id, entity_id, ownership_percentage) VALUES ('2d7523da-2a80-58f0-8adf-47e61b18c555', '482d4ffd-8015-52c8-99bb-0df3e53daded', '4a692464-d076-5c32-b162-63dcff4268f8', 50.00);
INSERT INTO public.fact_find_home_contents_ownership (id, home_contents_id, entity_id, ownership_percentage) VALUES ('82de4b18-6c74-5c3c-886b-a3833303c3fc', '482d4ffd-8015-52c8-99bb-0df3e53daded', 'f5c5e9a6-2d1c-5e46-b2a1-46e684e46995', 50.00);
INSERT INTO public.fact_find_home_contents_ownership (id, home_contents_id, entity_id, ownership_percentage) VALUES ('204007d2-ed12-08b4-4a46-d02207bdd85f', '94605cd3-88e8-fdc6-520b-ca792aa9c15a', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);
INSERT INTO public.fact_find_home_contents_ownership (id, home_contents_id, entity_id, ownership_percentage) VALUES ('2dc14326-7f36-4bf1-835b-28a9a8380d09', '44ffca82-e941-4a31-8f05-92b0a8b840d1', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);


--
-- Data for Name: fact_find_insurance_policy; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: fact_find_insurance_policy_feature; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: fact_find_insurance_policy_item; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: fact_find_insurance_policy_ownership; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: fact_find_investment_holding; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_investment_holding (id, investment_option_id, investment_platform_id, retirement_asset_id, superannuation_id, quantity, created_at, updated_at) VALUES ('59fc90ef-8867-4bde-9643-f48598d39226', '7ff8ed78-894f-4b96-af6d-7146417752a2', '7f2d2d86-47be-4af6-8552-63c53e21e509', NULL, NULL, 250.00000000, '2026-10-07 02:17:31.919164+00', '2026-10-07 02:17:31.911821+00');
INSERT INTO public.fact_find_investment_holding (id, investment_option_id, investment_platform_id, retirement_asset_id, superannuation_id, quantity, created_at, updated_at) VALUES ('a8809239-da63-4b51-a67e-0e921085fc54', '1b0a107e-2590-4d64-ad7b-fba265d21861', '7f2d2d86-47be-4af6-8552-63c53e21e509', NULL, NULL, 5000.00000000, '2026-10-07 02:17:31.965119+00', '2026-10-07 02:17:31.911821+00');


--
-- Data for Name: fact_find_investment_income; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_investment_income (id, name, income_amount, investment_type, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('92e45131-351f-5536-bf3d-1297c31378a5', 'Joint ETF distributions', 6300.00, 'ETF', false, NULL, NULL, NULL);
INSERT INTO public.fact_find_investment_income (id, name, income_amount, investment_type, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('02f55378-93ac-57e0-844b-e088f081531e', 'Australian dividends', 11600.00, 'Shares', NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_investment_income (id, name, income_amount, investment_type, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('018b1ae6-c286-51fe-a79d-aaa71015ba11', 'Term deposit interest', 4800.00, 'Term deposit', NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_investment_income (id, name, income_amount, investment_type, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('cbf2c519-412b-52d7-851a-8292ed48f1e8', 'ETF distributions', 3300.00, 'ETF', true, 600.00, 'Additional contributions', NULL);
INSERT INTO public.fact_find_investment_income (id, name, income_amount, investment_type, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('bdbabcfc-7b5c-50b8-b710-a8a12f01f1a5', 'Joint bond interest', 5200.00, 'Bonds', NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_investment_income (id, name, income_amount, investment_type, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('5a2b73e6-7c7e-e6ef-395f-2537055b5464', 'Share portfolio dividends', 6200.00, NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_investment_income (id, name, income_amount, investment_type, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('6037a5aa-b4c5-4874-9a7d-06e9b292223a', 'Australian dividends', 11600.00, 'Shares', NULL, NULL, NULL, '6e7ac885-bf77-40d9-bb9a-7a827827bf66');
INSERT INTO public.fact_find_investment_income (id, name, income_amount, investment_type, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('7e741d65-3ea4-47b4-ac86-2b4b1f25ed31', 'Share portfolio dividends', 6200.00, NULL, NULL, NULL, NULL, '6e7ac885-bf77-40d9-bb9a-7a827827bf66');


--
-- Data for Name: fact_find_investment_income_ownership; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_investment_income_ownership (id, investment_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('335e76a5-07ce-5de0-9fb7-bd07fd7ad32c', '92e45131-351f-5536-bf3d-1297c31378a5', '4472ba0b-7901-5e0e-af0a-812c347e574f', 50.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_investment_income_ownership (id, investment_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('1071a290-1bd5-5bd3-a0f9-6917c03ba5c1', '92e45131-351f-5536-bf3d-1297c31378a5', 'd40656e0-fd5c-584f-8452-c9d8ce20610d', 50.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_investment_income_ownership (id, investment_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('d5e401ba-0201-5378-a24f-39358e1c6955', '02f55378-93ac-57e0-844b-e088f081531e', '0214f9b3-de82-52b5-b213-b825b2dfdf7c', 100.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_investment_income_ownership (id, investment_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('9d2e5792-ecd0-5874-be6a-daadab2d15c9', '018b1ae6-c286-51fe-a79d-aaa71015ba11', 'a97799ee-e702-5031-ad8f-b80d762cec5a', 100.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_investment_income_ownership (id, investment_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('02d53c14-f224-54bb-8a50-69261bd71ad4', 'cbf2c519-412b-52d7-851a-8292ed48f1e8', '1a2b7fd2-5f8f-5d8c-baf3-0e2ecf017997', 100.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_investment_income_ownership (id, investment_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('e058a2dc-80c7-5ca2-95a2-f50fb9ec7e4d', 'bdbabcfc-7b5c-50b8-b710-a8a12f01f1a5', '8b0ef68e-dba1-57ee-9af3-50f7839669a4', 50.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_investment_income_ownership (id, investment_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('04067786-1f3f-5622-b176-30da778d3a16', 'bdbabcfc-7b5c-50b8-b710-a8a12f01f1a5', 'ea87fa5d-abe4-5a46-b31e-d036cc2abc8a', 50.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_investment_income_ownership (id, investment_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('d9ba82b5-dad1-887f-cf1b-49a70a00d9a1', '5a2b73e6-7c7e-e6ef-395f-2537055b5464', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00');
INSERT INTO public.fact_find_investment_income_ownership (id, investment_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('403cbf4e-4d43-4c1a-b310-a03ea731d112', '6037a5aa-b4c5-4874-9a7d-06e9b292223a', '0214f9b3-de82-52b5-b213-b825b2dfdf7c', 100.00, '2026-10-06 08:03:27.500375+00', '2026-10-06 08:03:27.500376+00');
INSERT INTO public.fact_find_investment_income_ownership (id, investment_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('5cf84b17-472b-4b8e-ab5b-683fe378b232', '7e741d65-3ea4-47b4-ac86-2b4b1f25ed31', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00, '2026-10-06 08:03:27.501899+00', '2026-10-06 08:03:27.5019+00');


--
-- Data for Name: fact_find_investment_platform; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_investment_platform (id, name, provider_name, product_name, account_number, account_type, account_established_date, opening_balance, account_balance, total_fees, administration_fee_amount, administration_fee_percent, adviser_fee_amount, adviser_fee_percent, trustee_fee_amount, issuer_fee_amount, expense_recovery_fee_amount, expense_recovery_fee_percent, fund_accounting_fee_amount, fund_accounting_fee_percent, asset_fee_percent, contribution_fee_percent, exit_withdrawal_fee_amount, exit_withdrawal_fee_percent, brokerage_buy_fee_amount, brokerage_buy_fee_percent, brokerage_sell_fee_amount, brokerage_sell_fee_percent, buy_sell_spread_amount, switch_fee_amount, client_notes, financial_planner_notes, case_id, financial_product_id, legacy_account_balance, holdings_configured) VALUES ('9eca6718-f8be-59f3-92bd-d86f81d15041', 'Family investment account', 'HUB24', 'HUB24 Invest', 'HUB-44550', 'Investment platform', '2020-09-15', 180000.00, NULL, 2900.00, 1100.00, NULL, 1800.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '30214bb9-671c-4788-bfb5-669560c02849', 295000.00, false);
INSERT INTO public.fact_find_investment_platform (id, name, provider_name, product_name, account_number, account_type, account_established_date, opening_balance, account_balance, total_fees, administration_fee_amount, administration_fee_percent, adviser_fee_amount, adviser_fee_percent, trustee_fee_amount, issuer_fee_amount, expense_recovery_fee_amount, expense_recovery_fee_percent, fund_accounting_fee_amount, fund_accounting_fee_percent, asset_fee_percent, contribution_fee_percent, exit_withdrawal_fee_amount, exit_withdrawal_fee_percent, brokerage_buy_fee_amount, brokerage_buy_fee_percent, brokerage_sell_fee_amount, brokerage_sell_fee_percent, buy_sell_spread_amount, switch_fee_amount, client_notes, financial_planner_notes, case_id, financial_product_id, legacy_account_balance, holdings_configured) VALUES ('795abce7-fcab-ad05-bf79-74b0e02555b4', 'Diversified investment account', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '94b13130-75fc-1e89-e746-6fe3e104ad5f', 145000.00, false);
INSERT INTO public.fact_find_investment_platform (id, name, provider_name, product_name, account_number, account_type, account_established_date, opening_balance, account_balance, total_fees, administration_fee_amount, administration_fee_percent, adviser_fee_amount, adviser_fee_percent, trustee_fee_amount, issuer_fee_amount, expense_recovery_fee_amount, expense_recovery_fee_percent, fund_accounting_fee_amount, fund_accounting_fee_percent, asset_fee_percent, contribution_fee_percent, exit_withdrawal_fee_amount, exit_withdrawal_fee_percent, brokerage_buy_fee_amount, brokerage_buy_fee_percent, brokerage_sell_fee_amount, brokerage_sell_fee_percent, buy_sell_spread_amount, switch_fee_amount, client_notes, financial_planner_notes, case_id, financial_product_id, legacy_account_balance, holdings_configured) VALUES ('7f2d2d86-47be-4af6-8552-63c53e21e509', 'Diversified investment account', NULL, NULL, NULL, NULL, NULL, NULL, 5250.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '6e7ac885-bf77-40d9-bb9a-7a827827bf66', 'b14013a9-592c-4ddd-be8a-1f4e734a863e', 145000.00, true);


--
-- Data for Name: fact_find_investment_platform_item; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_investment_platform_item (id, investment_platform_id, name, fund_option, current_value, allocation_percentage, financial_product_id) VALUES ('8e633fb0-26db-5cdd-82d5-e3922c6b8577', '9eca6718-f8be-59f3-92bd-d86f81d15041', 'Australian equities', 'Vanguard Australian Shares', 118000.00, 40.0000, NULL);
INSERT INTO public.fact_find_investment_platform_item (id, investment_platform_id, name, fund_option, current_value, allocation_percentage, financial_product_id) VALUES ('12a7ae69-f4a2-584d-aaad-8f513033402a', '9eca6718-f8be-59f3-92bd-d86f81d15041', 'International equities', 'Vanguard International Shares', 132750.00, 45.0000, NULL);
INSERT INTO public.fact_find_investment_platform_item (id, investment_platform_id, name, fund_option, current_value, allocation_percentage, financial_product_id) VALUES ('518002bf-3b5e-51ed-9a22-7a3a583049e4', '9eca6718-f8be-59f3-92bd-d86f81d15041', 'Fixed interest', 'Diversified Bonds', 44250.00, 15.0000, NULL);
INSERT INTO public.fact_find_investment_platform_item (id, investment_platform_id, name, fund_option, current_value, allocation_percentage, financial_product_id) VALUES ('de5272ba-a18f-e7ad-8b71-de33105ae265', '795abce7-fcab-ad05-bf79-74b0e02555b4', 'Balanced Opportunities Fund', NULL, 87000.00, 60.0000, 'e29fb477-c8e2-14db-e922-863c434ffa82');
INSERT INTO public.fact_find_investment_platform_item (id, investment_platform_id, name, fund_option, current_value, allocation_percentage, financial_product_id) VALUES ('3abba126-54e2-123f-98e7-0cf59fc0bf85', '795abce7-fcab-ad05-bf79-74b0e02555b4', 'Global Equity Index', NULL, 58000.00, 40.0000, '8bc8398a-66f6-cf50-aabf-8b3123d197f9');
INSERT INTO public.fact_find_investment_platform_item (id, investment_platform_id, name, fund_option, current_value, allocation_percentage, financial_product_id) VALUES ('12ccf95b-3bd1-4dc2-a24d-92267b7d046c', '7f2d2d86-47be-4af6-8552-63c53e21e509', 'Balanced Opportunities Fund', NULL, 87000.00, 60.0000, 'e29fb477-c8e2-14db-e922-863c434ffa82');
INSERT INTO public.fact_find_investment_platform_item (id, investment_platform_id, name, fund_option, current_value, allocation_percentage, financial_product_id) VALUES ('f4977575-7aee-4a8f-9d23-bf08a42d6182', '7f2d2d86-47be-4af6-8552-63c53e21e509', 'Global Equity Index', NULL, 58000.00, 40.0000, '8bc8398a-66f6-cf50-aabf-8b3123d197f9');


--
-- Data for Name: fact_find_investment_platform_ownership; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_investment_platform_ownership (id, investment_platform_id, entity_id, ownership_percentage) VALUES ('77e18381-ea91-5fa7-9338-d46e4c8ebecc', '9eca6718-f8be-59f3-92bd-d86f81d15041', '4a692464-d076-5c32-b162-63dcff4268f8', 50.00);
INSERT INTO public.fact_find_investment_platform_ownership (id, investment_platform_id, entity_id, ownership_percentage) VALUES ('3e34262c-f276-538d-919f-0c558e9011c9', '9eca6718-f8be-59f3-92bd-d86f81d15041', 'f5c5e9a6-2d1c-5e46-b2a1-46e684e46995', 50.00);
INSERT INTO public.fact_find_investment_platform_ownership (id, investment_platform_id, entity_id, ownership_percentage) VALUES ('ca795352-c8fe-3b91-ec7e-464e2646ed3b', '795abce7-fcab-ad05-bf79-74b0e02555b4', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);
INSERT INTO public.fact_find_investment_platform_ownership (id, investment_platform_id, entity_id, ownership_percentage) VALUES ('7ab0838f-2c78-4578-b56b-7c2020db903b', '7f2d2d86-47be-4af6-8552-63c53e21e509', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);


--
-- Data for Name: fact_find_occupational_income; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_occupational_income (id, name, allowance_amount, base_salary, bonus_amount, commission_amount, employment_id, salary_sacrifice_amount, superannuation_guarantee_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('7cec2f48-919d-5d30-beb8-0683889fab76', 'Product manager salary', NULL, 124000.00, 12000.00, NULL, NULL, 6000.00, 14880.00, true, 8000.00, 'Promotion', NULL);
INSERT INTO public.fact_find_occupational_income (id, name, allowance_amount, base_salary, bonus_amount, commission_amount, employment_id, salary_sacrifice_amount, superannuation_guarantee_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('75d447ce-40be-5b6e-89d4-9ebb4abc980e', 'Teacher salary', 2200.00, 101000.00, NULL, NULL, NULL, NULL, 12120.00, false, NULL, NULL, NULL);
INSERT INTO public.fact_find_occupational_income (id, name, allowance_amount, base_salary, bonus_amount, commission_amount, employment_id, salary_sacrifice_amount, superannuation_guarantee_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('e05f0058-0464-516a-82ee-e3927c8b65d0', 'Part-time employment', NULL, 49000.00, NULL, NULL, NULL, NULL, 5880.00, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_occupational_income (id, name, allowance_amount, base_salary, bonus_amount, commission_amount, employment_id, salary_sacrifice_amount, superannuation_guarantee_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('ec4be526-4af9-50c3-aa0e-9f7f5bac3157', 'Engineering salary', NULL, 156000.00, 16000.00, NULL, NULL, NULL, 18720.00, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_occupational_income (id, name, allowance_amount, base_salary, bonus_amount, commission_amount, employment_id, salary_sacrifice_amount, superannuation_guarantee_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('cd694052-6554-541e-a821-48fb37d50cde', 'Account executive salary', NULL, 78000.00, NULL, 35000.00, NULL, NULL, 9360.00, true, 10000.00, 'Growing sales pipeline', NULL);
INSERT INTO public.fact_find_occupational_income (id, name, allowance_amount, base_salary, bonus_amount, commission_amount, employment_id, salary_sacrifice_amount, superannuation_guarantee_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('332d1cbf-ac13-5e33-9f8a-ab3b644cf38e', 'Casual teaching', NULL, 24000.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_occupational_income (id, name, allowance_amount, base_salary, bonus_amount, commission_amount, employment_id, salary_sacrifice_amount, superannuation_guarantee_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('a10dcc39-483d-54e5-b100-c7a9c25657e9', 'Healthcare salary', 4000.00, 92000.00, NULL, NULL, NULL, 9000.00, 11040.00, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_occupational_income (id, name, allowance_amount, base_salary, bonus_amount, commission_amount, employment_id, salary_sacrifice_amount, superannuation_guarantee_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('8ad9986a-fd99-5e52-962e-087b299d52ce', 'Operations director salary', NULL, 138000.00, 10000.00, NULL, NULL, NULL, 16560.00, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_occupational_income (id, name, allowance_amount, base_salary, bonus_amount, commission_amount, employment_id, salary_sacrifice_amount, superannuation_guarantee_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('9eca814e-b412-63c8-002a-b01b1aa496f9', 'Senior architect — Linden Urban Design', 2400.00, 168000.00, 12000.00, NULL, NULL, 6000.00, 20160.00, false, NULL, NULL, NULL);
INSERT INTO public.fact_find_occupational_income (id, name, allowance_amount, base_salary, bonus_amount, commission_amount, employment_id, salary_sacrifice_amount, superannuation_guarantee_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('89fc9c12-3d13-d8ac-2735-b6ebb6bf88a9', 'Design director — Hartley Design Studio', NULL, 124000.00, NULL, NULL, NULL, NULL, 14880.00, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_occupational_income (id, name, allowance_amount, base_salary, bonus_amount, commission_amount, employment_id, salary_sacrifice_amount, superannuation_guarantee_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('9bf0fa25-5a3e-f19d-e27e-716997c7511f', 'Consultant surgeon — Riverside Surgical Group', NULL, 365000.00, 45000.00, NULL, NULL, NULL, 30000.00, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_occupational_income (id, name, allowance_amount, base_salary, bonus_amount, commission_amount, employment_id, salary_sacrifice_amount, superannuation_guarantee_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('1dd5b239-9a4e-bd10-01a2-3711ee50a348', 'Operations manager — Coastline Logistics', NULL, 92000.00, NULL, NULL, NULL, NULL, 11040.00, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_occupational_income (id, name, allowance_amount, base_salary, bonus_amount, commission_amount, employment_id, salary_sacrifice_amount, superannuation_guarantee_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('6d46318f-725f-eb32-1157-bdbf73c90dcc', 'Graduate engineer — Hinterland Engineering', NULL, 76000.00, NULL, NULL, NULL, NULL, 9120.00, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_occupational_income (id, name, allowance_amount, base_salary, bonus_amount, commission_amount, employment_id, salary_sacrifice_amount, superannuation_guarantee_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('7f48fdd1-6a66-4732-a148-87152bd7f9a8', 'Engineering salary', NULL, 156000.00, 16000.00, NULL, NULL, NULL, 18720.00, NULL, NULL, NULL, '6e7ac885-bf77-40d9-bb9a-7a827827bf66');
INSERT INTO public.fact_find_occupational_income (id, name, allowance_amount, base_salary, bonus_amount, commission_amount, employment_id, salary_sacrifice_amount, superannuation_guarantee_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('c67e2fbf-7214-4eb0-8a53-668bb8f70610', 'Senior architect — Linden Urban Design', 2400.00, 168000.00, 12000.00, NULL, NULL, 6000.00, 20160.00, false, NULL, NULL, '6e7ac885-bf77-40d9-bb9a-7a827827bf66');


--
-- Data for Name: fact_find_occupational_income_ownership; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_occupational_income_ownership (id, occupational_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('d14dd5a9-ede0-5e84-b0da-d5265273c91a', '7cec2f48-919d-5d30-beb8-0683889fab76', '4472ba0b-7901-5e0e-af0a-812c347e574f', 100.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_occupational_income_ownership (id, occupational_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('8f98fcff-17f9-52f8-bbc3-5676770de866', '75d447ce-40be-5b6e-89d4-9ebb4abc980e', 'd40656e0-fd5c-584f-8452-c9d8ce20610d', 100.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_occupational_income_ownership (id, occupational_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('9d4f7140-a6df-5bff-8eda-363877c4dadd', 'e05f0058-0464-516a-82ee-e3927c8b65d0', 'e2fb9ead-5c3d-5f07-9030-2eb109ea027b', 100.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_occupational_income_ownership (id, occupational_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('27a68469-467f-5073-a91f-bf3b69345fcb', 'ec4be526-4af9-50c3-aa0e-9f7f5bac3157', '0214f9b3-de82-52b5-b213-b825b2dfdf7c', 100.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_occupational_income_ownership (id, occupational_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('7d57830f-cce6-57cc-a8b9-bafcce23ef87', 'cd694052-6554-541e-a821-48fb37d50cde', 'aff315ca-e674-5e50-8a58-b4b697c78301', 100.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_occupational_income_ownership (id, occupational_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('c5f4e4c1-6a18-51e6-837d-2e40b666a444', '332d1cbf-ac13-5e33-9f8a-ab3b644cf38e', '2fd1c862-d355-514c-a415-c30dd66168ef', 100.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_occupational_income_ownership (id, occupational_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('958dfc88-d964-5ec6-9691-97af8b60138c', 'a10dcc39-483d-54e5-b100-c7a9c25657e9', '1a2b7fd2-5f8f-5d8c-baf3-0e2ecf017997', 100.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_occupational_income_ownership (id, occupational_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('a7479b91-4232-5b11-a787-deca219b09e6', '8ad9986a-fd99-5e52-962e-087b299d52ce', '8b0ef68e-dba1-57ee-9af3-50f7839669a4', 100.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_occupational_income_ownership (id, occupational_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('0bc1382f-375d-31db-51e0-feed652bc8e1', '9eca814e-b412-63c8-002a-b01b1aa496f9', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00');
INSERT INTO public.fact_find_occupational_income_ownership (id, occupational_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('a0d291b6-e54d-0ddd-e7ea-804d2119fbeb', '89fc9c12-3d13-d8ac-2735-b6ebb6bf88a9', '928618c6-fbe9-cefb-b909-8749139aba74', 100.00, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00');
INSERT INTO public.fact_find_occupational_income_ownership (id, occupational_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('647414eb-49d5-d565-7160-74a6440a339f', '9bf0fa25-5a3e-f19d-e27e-716997c7511f', '5876e49c-a05e-e482-b1c4-109d4f0d768f', 100.00, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00');
INSERT INTO public.fact_find_occupational_income_ownership (id, occupational_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('da95d31d-616c-9c5f-e3b4-f286b5e1c0b2', '1dd5b239-9a4e-bd10-01a2-3711ee50a348', 'ddbc9aa9-d048-17b2-5335-9682d9601396', 100.00, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00');
INSERT INTO public.fact_find_occupational_income_ownership (id, occupational_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('dbf302d2-10d9-51eb-9edc-9e0ea50b1ae1', '6d46318f-725f-eb32-1157-bdbf73c90dcc', '89c9b482-62a4-4b1b-fadb-8947c86522b1', 100.00, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00');
INSERT INTO public.fact_find_occupational_income_ownership (id, occupational_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('699f5a4b-84c4-4676-8c32-06641c5b3e29', '7f48fdd1-6a66-4732-a148-87152bd7f9a8', '0214f9b3-de82-52b5-b213-b825b2dfdf7c', 100.00, '2026-10-06 08:03:27.51471+00', '2026-10-06 08:03:27.514711+00');
INSERT INTO public.fact_find_occupational_income_ownership (id, occupational_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('daa09458-f5b0-43ab-9c8c-754b66ccd762', 'c67e2fbf-7214-4eb0-8a53-668bb8f70610', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00, '2026-10-06 08:03:27.516237+00', '2026-10-06 08:03:27.516238+00');


--
-- Data for Name: fact_find_other_asset; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_other_asset (id, name, current_market_value, client_notes, financial_planner_notes, case_id) VALUES ('d42a5123-e40b-5702-8081-78561826f951', 'Watch collection', 22000.00, 'Insured separately', NULL, NULL);
INSERT INTO public.fact_find_other_asset (id, name, current_market_value, client_notes, financial_planner_notes, case_id) VALUES ('39c36f52-3834-e846-2ee4-d61420b77581', 'Australian landscape collection', 22000.00, NULL, NULL, NULL);
INSERT INTO public.fact_find_other_asset (id, name, current_market_value, client_notes, financial_planner_notes, case_id) VALUES ('ab5ee63a-fd3e-47e3-a4ac-7e61b196a0a6', 'Australian landscape collection', 22000.00, NULL, NULL, '6e7ac885-bf77-40d9-bb9a-7a827827bf66');


--
-- Data for Name: fact_find_other_asset_ownership; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_other_asset_ownership (id, other_asset_id, entity_id, ownership_percentage) VALUES ('1e51e5bb-221e-57d4-b39a-1dfe477aef12', 'd42a5123-e40b-5702-8081-78561826f951', '4a692464-d076-5c32-b162-63dcff4268f8', 100.00);
INSERT INTO public.fact_find_other_asset_ownership (id, other_asset_id, entity_id, ownership_percentage) VALUES ('5db803f3-fb9f-871a-4aec-c18d21616f82', '39c36f52-3834-e846-2ee4-d61420b77581', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);
INSERT INTO public.fact_find_other_asset_ownership (id, other_asset_id, entity_id, ownership_percentage) VALUES ('d9ee5a96-96e5-421a-b4ff-083bccb9f13a', 'ab5ee63a-fd3e-47e3-a4ac-7e61b196a0a6', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);


--
-- Data for Name: fact_find_other_income; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_other_income (id, name, non_taxable_income_amount, source_of_non_taxable_income, taxable_income_amount, taxable_income_flag, source_of_taxable_income, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('a05ed42e-581e-5915-9835-5f07b68d423e', 'Study stipend', 5200.00, 'Scholarship', NULL, false, NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_other_income (id, name, non_taxable_income_amount, source_of_non_taxable_income, taxable_income_amount, taxable_income_flag, source_of_taxable_income, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('a15cc7ad-4087-5cda-8804-2518ab28dbcd', 'Book royalties', NULL, NULL, 3100.00, true, 'Publishing royalties', NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_other_income (id, name, non_taxable_income_amount, source_of_non_taxable_income, taxable_income_amount, taxable_income_flag, source_of_taxable_income, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('a6083752-33b9-5439-99f7-18ade06f602a', 'Photography licensing', NULL, NULL, 2200.00, true, 'Image licensing', true, -300.00, 'Fewer licences', NULL);
INSERT INTO public.fact_find_other_income (id, name, non_taxable_income_amount, source_of_non_taxable_income, taxable_income_amount, taxable_income_flag, source_of_taxable_income, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('f13584c0-77e0-53e7-94ad-923a9c80fa78', 'Family support', 4800.00, 'Family gifts', NULL, false, NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_other_income (id, name, non_taxable_income_amount, source_of_non_taxable_income, taxable_income_amount, taxable_income_flag, source_of_taxable_income, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('0098a03c-8923-dfec-5145-e4e06373e137', 'Architecture mentoring honorarium', NULL, NULL, 2400.00, true, NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_other_income (id, name, non_taxable_income_amount, source_of_non_taxable_income, taxable_income_amount, taxable_income_flag, source_of_taxable_income, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('f37aab48-1072-4d93-bcc4-8cab7e0efea0', 'Architecture mentoring honorarium', NULL, NULL, 2400.00, true, NULL, NULL, NULL, NULL, '6e7ac885-bf77-40d9-bb9a-7a827827bf66');


--
-- Data for Name: fact_find_other_income_ownership; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_other_income_ownership (id, other_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('f723702e-5b80-5d7f-86c6-8624447b33b8', 'a05ed42e-581e-5915-9835-5f07b68d423e', 'e2fb9ead-5c3d-5f07-9030-2eb109ea027b', 100.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_other_income_ownership (id, other_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('f268d505-c742-5c0a-a62e-f24bff1c068f', 'a15cc7ad-4087-5cda-8804-2518ab28dbcd', 'b15a9373-b775-5211-afbf-1bceea904a95', 100.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_other_income_ownership (id, other_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('0759ffb6-b392-55c6-8a31-8ca7d1bec339', 'a6083752-33b9-5439-99f7-18ade06f602a', '2fd1c862-d355-514c-a415-c30dd66168ef', 100.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_other_income_ownership (id, other_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('ba02cb4a-5c10-59fd-8556-b6f58ecdc2ec', 'f13584c0-77e0-53e7-94ad-923a9c80fa78', 'f9438f7c-a8e5-5839-8673-057ba714d3a0', 100.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_other_income_ownership (id, other_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('908b2420-4524-4d85-acfa-7780088104ab', '0098a03c-8923-dfec-5145-e4e06373e137', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00');
INSERT INTO public.fact_find_other_income_ownership (id, other_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('3facb4aa-5e0f-4eb0-b53b-0913835f4b88', 'f37aab48-1072-4d93-bcc4-8cab7e0efea0', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00, '2026-10-06 08:03:27.525963+00', '2026-10-06 08:03:27.525964+00');


--
-- Data for Name: fact_find_other_liability; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_other_liability (id, name, liability_type, current_balance, repayment_amount, repayment_frequency, client_notes, financial_planner_notes, case_id) VALUES ('82eb1333-3447-5226-8f92-dc578b70a4ff', 'ATO payment plan', 'Tax debt', 8500.00, 750.00, 'monthly', NULL, NULL, NULL);
INSERT INTO public.fact_find_other_liability (id, name, liability_type, current_balance, repayment_amount, repayment_frequency, client_notes, financial_planner_notes, case_id) VALUES ('26147244-9840-c3b8-51ec-2b3bbf6bfc5e', 'Quarterly tax provision', NULL, 4200.00, NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_other_liability (id, name, liability_type, current_balance, repayment_amount, repayment_frequency, client_notes, financial_planner_notes, case_id) VALUES ('74111a14-140e-4206-9ac2-983f2822542c', 'Quarterly tax provision', NULL, 4200.00, NULL, NULL, NULL, NULL, '6e7ac885-bf77-40d9-bb9a-7a827827bf66');


--
-- Data for Name: fact_find_other_liability_ownership; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_other_liability_ownership (id, other_liability_id, entity_id, ownership_percentage) VALUES ('a650c202-28d2-5dff-9abd-afbd98380bad', '82eb1333-3447-5226-8f92-dc578b70a4ff', '4a692464-d076-5c32-b162-63dcff4268f8', 100.00);
INSERT INTO public.fact_find_other_liability_ownership (id, other_liability_id, entity_id, ownership_percentage) VALUES ('37245567-7b2a-7d74-abf7-3b68e2cee92e', '26147244-9840-c3b8-51ec-2b3bbf6bfc5e', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);
INSERT INTO public.fact_find_other_liability_ownership (id, other_liability_id, entity_id, ownership_percentage) VALUES ('baa0bc08-ec67-4ada-b858-eba97839bbc0', '74111a14-140e-4206-9ac2-983f2822542c', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);


--
-- Data for Name: fact_find_personal_loan; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_personal_loan (id, name, provider, product_name, loan_type, establishment_date, original_loan_amount, current_balance, current_interest_rate, original_loan_term, remaining_loan_term, repayment_amount, repayment_frequency, redraw_amount, redraw_fee, account_fee, monthly_fee, exit_fee, other_fee, guarantor, tax_deductible, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('adf6e9ab-6eac-5287-8fc5-9a7d9eb0e8aa', 'Renovation loan', 'NAB', 'Personal Loan', 'Unsecured', '2025-02-01', 30000.00, 18500.00, 9.2000, '5 years', '3.5 years', 640.00, 'monthly', NULL, NULL, NULL, NULL, NULL, NULL, NULL, false, NULL, NULL, NULL, 'f8eccf88-310d-4043-86fd-fb755a081169');
INSERT INTO public.fact_find_personal_loan (id, name, provider, product_name, loan_type, establishment_date, original_loan_amount, current_balance, current_interest_rate, original_loan_term, remaining_loan_term, repayment_amount, repayment_frequency, redraw_amount, redraw_fee, account_fee, monthly_fee, exit_fee, other_fee, guarantor, tax_deductible, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('86c17bd9-334c-5d95-5c8c-dfc0e57af5a5', 'Kitchen renovation loan', NULL, NULL, NULL, NULL, NULL, 14500.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'ee67655b-8eeb-0e0e-ec3a-0ec33bbbb464');
INSERT INTO public.fact_find_personal_loan (id, name, provider, product_name, loan_type, establishment_date, original_loan_amount, current_balance, current_interest_rate, original_loan_term, remaining_loan_term, repayment_amount, repayment_frequency, redraw_amount, redraw_fee, account_fee, monthly_fee, exit_fee, other_fee, guarantor, tax_deductible, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('dc271a23-dd66-46e3-2b62-bcc6e56d8d61', 'Debt consolidation loan', NULL, NULL, NULL, NULL, NULL, 23500.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'ee67655b-8eeb-0e0e-ec3a-0ec33bbbb464');
INSERT INTO public.fact_find_personal_loan (id, name, provider, product_name, loan_type, establishment_date, original_loan_amount, current_balance, current_interest_rate, original_loan_term, remaining_loan_term, repayment_amount, repayment_frequency, redraw_amount, redraw_fee, account_fee, monthly_fee, exit_fee, other_fee, guarantor, tax_deductible, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('f7c7bd31-abb0-475f-b061-894c2cc7fede', 'loan', NULL, NULL, 'Loan', NULL, NULL, 3000.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'f8eccf88-310d-4043-86fd-fb755a081169');
INSERT INTO public.fact_find_personal_loan (id, name, provider, product_name, loan_type, establishment_date, original_loan_amount, current_balance, current_interest_rate, original_loan_term, remaining_loan_term, repayment_amount, repayment_frequency, redraw_amount, redraw_fee, account_fee, monthly_fee, exit_fee, other_fee, guarantor, tax_deductible, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('4a864339-fa30-4243-9a7d-8bcbe076cbd4', 'Kitchen renovation loan', NULL, NULL, NULL, NULL, NULL, 14500.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '6e7ac885-bf77-40d9-bb9a-7a827827bf66', 'ee67655b-8eeb-0e0e-ec3a-0ec33bbbb464');
INSERT INTO public.fact_find_personal_loan (id, name, provider, product_name, loan_type, establishment_date, original_loan_amount, current_balance, current_interest_rate, original_loan_term, remaining_loan_term, repayment_amount, repayment_frequency, redraw_amount, redraw_fee, account_fee, monthly_fee, exit_fee, other_fee, guarantor, tax_deductible, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('bff02fdd-33ac-400f-befa-393cc4708428', 'loan', NULL, NULL, 'Loan', NULL, NULL, 3000.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '6e7ac885-bf77-40d9-bb9a-7a827827bf66', 'f8eccf88-310d-4043-86fd-fb755a081169');


--
-- Data for Name: fact_find_personal_loan_ownership; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_personal_loan_ownership (id, personal_loan_id, entity_id, ownership_percentage) VALUES ('98f83456-2a83-5174-8c5c-bf141aea43b4', 'adf6e9ab-6eac-5287-8fc5-9a7d9eb0e8aa', '4a692464-d076-5c32-b162-63dcff4268f8', 100.00);
INSERT INTO public.fact_find_personal_loan_ownership (id, personal_loan_id, entity_id, ownership_percentage) VALUES ('5c481147-cb7d-2610-b0e5-fe71d8cf960d', '86c17bd9-334c-5d95-5c8c-dfc0e57af5a5', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);
INSERT INTO public.fact_find_personal_loan_ownership (id, personal_loan_id, entity_id, ownership_percentage) VALUES ('1f2eae0e-dc65-5c6f-dbff-3f1fe2babc51', 'dc271a23-dd66-46e3-2b62-bcc6e56d8d61', 'ddbc9aa9-d048-17b2-5335-9682d9601396', 100.00);
INSERT INTO public.fact_find_personal_loan_ownership (id, personal_loan_id, entity_id, ownership_percentage) VALUES ('edc4abe7-174d-4915-ae9f-46e058f8e136', 'f7c7bd31-abb0-475f-b061-894c2cc7fede', '0214f9b3-de82-52b5-b213-b825b2dfdf7c', 100.00);
INSERT INTO public.fact_find_personal_loan_ownership (id, personal_loan_id, entity_id, ownership_percentage) VALUES ('77032164-d583-42d8-997d-29ba6d546c39', '4a864339-fa30-4243-9a7d-8bcbe076cbd4', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);
INSERT INTO public.fact_find_personal_loan_ownership (id, personal_loan_id, entity_id, ownership_percentage) VALUES ('df77585c-5e40-4c77-b0e4-8ac96d8524b5', 'bff02fdd-33ac-400f-befa-393cc4708428', '0214f9b3-de82-52b5-b213-b825b2dfdf7c', 100.00);


--
-- Data for Name: fact_find_principal_residence; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_principal_residence (id, address_line1, address_line2, suburb, state, postcode, country, purchase_date, purchase_price, current_market_value, outstanding_loan_value, equity_available, estimated_annual_outgoings, client_notes, financial_planner_notes, case_id) VALUES ('f3dd304b-36b0-538e-be1e-d06d967cce8e', '12 Example Street', NULL, 'Castle Hill', 'NSW', '2154', 'Australia', '2019-06-15', 980000.00, 1450000.00, 620000.00, 830000.00, 8500.00, NULL, NULL, NULL);
INSERT INTO public.fact_find_principal_residence (id, address_line1, address_line2, suburb, state, postcode, country, purchase_date, purchase_price, current_market_value, outstanding_loan_value, equity_available, estimated_annual_outgoings, client_notes, financial_planner_notes, case_id) VALUES ('d8dd0f8b-2da6-11be-0320-b41fa67252d9', '18 Banksia Crescent', NULL, 'Lane Cove', 'NSW', '2066', 'Australia', '2017-06-14', 1250000.00, 1850000.00, NULL, NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_principal_residence (id, address_line1, address_line2, suburb, state, postcode, country, purchase_date, purchase_price, current_market_value, outstanding_loan_value, equity_available, estimated_annual_outgoings, client_notes, financial_planner_notes, case_id) VALUES ('55ffac50-68e0-4b24-808f-d8a432bcc765', '18 Banksia Crescent', NULL, 'Lane Cove', 'NSW', '2066', 'Australia', '2017-06-14', 1250000.00, 1850000.00, NULL, NULL, NULL, NULL, NULL, '6e7ac885-bf77-40d9-bb9a-7a827827bf66');


--
-- Data for Name: fact_find_principal_residence_ownership; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_principal_residence_ownership (id, principal_residence_id, entity_id, ownership_percentage) VALUES ('4dd1eac9-46b0-5381-8040-3625011b8158', 'f3dd304b-36b0-538e-be1e-d06d967cce8e', '4a692464-d076-5c32-b162-63dcff4268f8', 50.00);
INSERT INTO public.fact_find_principal_residence_ownership (id, principal_residence_id, entity_id, ownership_percentage) VALUES ('1435d790-1b63-5884-9634-208f513aff3b', 'f3dd304b-36b0-538e-be1e-d06d967cce8e', 'f5c5e9a6-2d1c-5e46-b2a1-46e684e46995', 50.00);
INSERT INTO public.fact_find_principal_residence_ownership (id, principal_residence_id, entity_id, ownership_percentage) VALUES ('b6002048-a727-46a1-af6c-a6d3f42d0859', 'd8dd0f8b-2da6-11be-0320-b41fa67252d9', '21340348-85a1-c72f-bdf1-0860c21d4b54', 50.00);
INSERT INTO public.fact_find_principal_residence_ownership (id, principal_residence_id, entity_id, ownership_percentage) VALUES ('55bdfa34-b9ca-705c-39a1-f861f0e1f031', 'd8dd0f8b-2da6-11be-0320-b41fa67252d9', '928618c6-fbe9-cefb-b909-8749139aba74', 50.00);
INSERT INTO public.fact_find_principal_residence_ownership (id, principal_residence_id, entity_id, ownership_percentage) VALUES ('3931e7b1-daf6-43bc-afd4-a396284804ec', '55ffac50-68e0-4b24-808f-d8a432bcc765', '21340348-85a1-c72f-bdf1-0860c21d4b54', 50.00);
INSERT INTO public.fact_find_principal_residence_ownership (id, principal_residence_id, entity_id, ownership_percentage) VALUES ('013d4982-433f-4e31-bc5d-c28a97d4ddba', '55ffac50-68e0-4b24-808f-d8a432bcc765', '928618c6-fbe9-cefb-b909-8749139aba74', 50.00);


--
-- Data for Name: fact_find_property_asset; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_property_asset (id, name, property_type, address_line1, address_line2, suburb, state, postcode, country, purchase_date, purchase_price, current_market_value, outstanding_loan_value, equity_available, rental_income_amount, rental_income_frequency, estimated_annual_outgoings, client_notes, financial_planner_notes, case_id) VALUES ('ff056c78-8870-5a9e-92c7-5e0e73b93b7f', 'Newcastle townhouse', 'Investment property', '22 Hunter Lane', NULL, 'Newcastle', 'NSW', '2300', 'Australia', '2022-08-01', 690000.00, 820000.00, 515000.00, 305000.00, 31200.00, 'annual', 8200.00, NULL, NULL, NULL);
INSERT INTO public.fact_find_property_asset (id, name, property_type, address_line1, address_line2, suburb, state, postcode, country, purchase_date, purchase_price, current_market_value, outstanding_loan_value, equity_available, rental_income_amount, rental_income_frequency, estimated_annual_outgoings, client_notes, financial_planner_notes, case_id) VALUES ('94b1c985-f43f-ba9b-4dee-21112f4d38bb', 'Newcastle rental unit', NULL, '9 Harbour View Road', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 680000.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_property_asset (id, name, property_type, address_line1, address_line2, suburb, state, postcode, country, purchase_date, purchase_price, current_market_value, outstanding_loan_value, equity_available, rental_income_amount, rental_income_frequency, estimated_annual_outgoings, client_notes, financial_planner_notes, case_id) VALUES ('9075df35-6d72-47a7-8a0f-54594cfe9c28', 'Newcastle rental unit', NULL, '9 Harbour View Road', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 680000.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '6e7ac885-bf77-40d9-bb9a-7a827827bf66');


--
-- Data for Name: fact_find_property_asset_ownership; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_property_asset_ownership (id, property_asset_id, entity_id, ownership_percentage) VALUES ('37c00bbe-5e6c-5b60-802f-15545bba1724', 'ff056c78-8870-5a9e-92c7-5e0e73b93b7f', '4a692464-d076-5c32-b162-63dcff4268f8', 100.00);
INSERT INTO public.fact_find_property_asset_ownership (id, property_asset_id, entity_id, ownership_percentage) VALUES ('080752f2-af52-76c4-f24e-0e872d68683b', '94b1c985-f43f-ba9b-4dee-21112f4d38bb', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);
INSERT INTO public.fact_find_property_asset_ownership (id, property_asset_id, entity_id, ownership_percentage) VALUES ('4264570d-e640-4f55-a1df-71115c7f4dab', '9075df35-6d72-47a7-8a0f-54594cfe9c28', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);


--
-- Data for Name: fact_find_property_income; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_property_income (id, name, income_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('247b416f-64d1-5efb-bda6-33202debfe8d', 'Parramatta investment apartment rent', 33800.00, true, 1800.00, 'Lease renewal', NULL);
INSERT INTO public.fact_find_property_income (id, name, income_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('002cc825-cdbf-5cf0-8830-0fc09ecb5db5', 'Newcastle townhouse rent', 31200.00, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_property_income (id, name, income_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('f8e598df-ee3c-5b26-8d6a-5fef6040a815', 'Brisbane unit rent', 28600.00, false, NULL, NULL, NULL);
INSERT INTO public.fact_find_property_income (id, name, income_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('621d4957-fb63-5638-a501-5af3e548362c', 'Perth investment house rent', 36400.00, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_property_income (id, name, income_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('c56493e7-0e99-620d-1448-67bcdfb79f50', 'Newcastle investment unit rent', 31200.00, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_property_income (id, name, income_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('5da99a7a-8e8d-4665-b445-5c1e26bc9751', 'Newcastle townhouse rent', 31200.00, NULL, NULL, NULL, '6e7ac885-bf77-40d9-bb9a-7a827827bf66');
INSERT INTO public.fact_find_property_income (id, name, income_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('a12fb3b1-7396-4be2-8f36-cc71bc7386af', 'Newcastle investment unit rent', 31200.00, NULL, NULL, NULL, '6e7ac885-bf77-40d9-bb9a-7a827827bf66');


--
-- Data for Name: fact_find_property_income_ownership; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_property_income_ownership (id, property_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('1b700337-dfa6-5f90-b35c-0c8a5e8a2de1', '247b416f-64d1-5efb-bda6-33202debfe8d', '4472ba0b-7901-5e0e-af0a-812c347e574f', 50.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_property_income_ownership (id, property_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('056e9474-1e2e-5a3e-9342-f321f2988f86', '247b416f-64d1-5efb-bda6-33202debfe8d', 'd40656e0-fd5c-584f-8452-c9d8ce20610d', 50.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_property_income_ownership (id, property_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('41cce950-a160-5939-a3fa-d6b127b3e9fb', '002cc825-cdbf-5cf0-8830-0fc09ecb5db5', '0214f9b3-de82-52b5-b213-b825b2dfdf7c', 100.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_property_income_ownership (id, property_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('03d54db0-9f0b-5b0b-8a98-0ddf6638165d', 'f8e598df-ee3c-5b26-8d6a-5fef6040a815', 'aff315ca-e674-5e50-8a58-b4b697c78301', 100.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_property_income_ownership (id, property_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('745a4ce5-f42c-55df-bd3f-b860d2cc7818', '621d4957-fb63-5638-a501-5af3e548362c', '8b0ef68e-dba1-57ee-9af3-50f7839669a4', 50.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_property_income_ownership (id, property_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('3080065e-ece6-5259-80dc-bf1a796ed50d', '621d4957-fb63-5638-a501-5af3e548362c', 'ea87fa5d-abe4-5a46-b31e-d036cc2abc8a', 50.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_property_income_ownership (id, property_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('adf150b1-510b-b5b2-54b6-b3771ce17981', 'c56493e7-0e99-620d-1448-67bcdfb79f50', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00');
INSERT INTO public.fact_find_property_income_ownership (id, property_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('89daeec6-760b-400e-bd03-eca614b34a28', '5da99a7a-8e8d-4665-b445-5c1e26bc9751', '0214f9b3-de82-52b5-b213-b825b2dfdf7c', 100.00, '2026-10-06 08:03:27.549262+00', '2026-10-06 08:03:27.549263+00');
INSERT INTO public.fact_find_property_income_ownership (id, property_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('3fa8cf45-368d-4e91-9184-9e7007b7ecee', 'a12fb3b1-7396-4be2-8f36-cc71bc7386af', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00, '2026-10-06 08:03:27.550622+00', '2026-10-06 08:03:27.550623+00');


--
-- Data for Name: fact_find_property_loan; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_property_loan (id, name, provider, product_name, loan_type, establishment_date, original_loan_amount, current_balance, current_interest_rate, original_loan_term, remaining_loan_term, repayment_amount, repayment_frequency, redraw_amount, redraw_fee, account_fee, monthly_fee, withdrawal_fee, exit_fee, other_fee, guarantor, tax_deductible, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('194ee2f0-d2f6-5cea-b477-4964c6586ca3', 'Home mortgage', 'Commonwealth Bank', 'Wealth Package Variable', 'Principal and interest', '2019-06-15', 784000.00, 620000.00, 5.8400, '30 years', '23 years', 3900.00, 'monthly', 12000.00, NULL, 395.00, NULL, NULL, NULL, NULL, NULL, false, NULL, NULL, NULL, '85387aef-f324-4643-bb9a-245b2f76b1e6');
INSERT INTO public.fact_find_property_loan (id, name, provider, product_name, loan_type, establishment_date, original_loan_amount, current_balance, current_interest_rate, original_loan_term, remaining_loan_term, repayment_amount, repayment_frequency, redraw_amount, redraw_fee, account_fee, monthly_fee, withdrawal_fee, exit_fee, other_fee, guarantor, tax_deductible, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('ab71494c-fbaf-5a7e-9052-a93beb6fd1ef', 'Newcastle investment loan', 'Macquarie', 'Variable Investment Loan', 'Interest only', '2022-08-01', 550000.00, 515000.00, 6.2500, '30 years', '26 years', 2682.00, 'monthly', 0.00, NULL, 0.00, NULL, NULL, NULL, NULL, NULL, true, NULL, NULL, NULL, '17a1ed61-fdd5-4600-8b13-d4c92c72d7bd');
INSERT INTO public.fact_find_property_loan (id, name, provider, product_name, loan_type, establishment_date, original_loan_amount, current_balance, current_interest_rate, original_loan_term, remaining_loan_term, repayment_amount, repayment_frequency, redraw_amount, redraw_fee, account_fee, monthly_fee, withdrawal_fee, exit_fee, other_fee, guarantor, tax_deductible, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('64a4a13b-f4db-1694-2c73-c8dad8c0390c', 'Home mortgage', NULL, NULL, 'Owner occupied', NULL, 920000.00, 640000.00, 5.8500, NULL, NULL, 4200.00, 'monthly', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'f9731a25-cb1e-a118-c126-b0e888297dd8');
INSERT INTO public.fact_find_property_loan (id, name, provider, product_name, loan_type, establishment_date, original_loan_amount, current_balance, current_interest_rate, original_loan_term, remaining_loan_term, repayment_amount, repayment_frequency, redraw_amount, redraw_fee, account_fee, monthly_fee, withdrawal_fee, exit_fee, other_fee, guarantor, tax_deductible, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('5d022f63-ac97-aad7-2cc4-8908079f2bf2', 'Rental unit mortgage', NULL, NULL, NULL, NULL, NULL, 395000.00, 6.1500, NULL, NULL, 2450.00, 'monthly', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, true, NULL, NULL, NULL, '33272370-cb48-31cd-5986-add8755d6842');
INSERT INTO public.fact_find_property_loan (id, name, provider, product_name, loan_type, establishment_date, original_loan_amount, current_balance, current_interest_rate, original_loan_term, remaining_loan_term, repayment_amount, repayment_frequency, redraw_amount, redraw_fee, account_fee, monthly_fee, withdrawal_fee, exit_fee, other_fee, guarantor, tax_deductible, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('5ae56d71-6715-42d1-89c3-3432bbe28dfe', 'Home mortgage', NULL, NULL, 'Owner occupied', NULL, 920000.00, 640000.00, 5.8500, NULL, NULL, 4200.00, 'monthly', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '6e7ac885-bf77-40d9-bb9a-7a827827bf66', 'f9731a25-cb1e-a118-c126-b0e888297dd8');
INSERT INTO public.fact_find_property_loan (id, name, provider, product_name, loan_type, establishment_date, original_loan_amount, current_balance, current_interest_rate, original_loan_term, remaining_loan_term, repayment_amount, repayment_frequency, redraw_amount, redraw_fee, account_fee, monthly_fee, withdrawal_fee, exit_fee, other_fee, guarantor, tax_deductible, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('82f2cda5-351b-4e7c-af42-ffa45312e3a5', 'Rental unit mortgage', NULL, NULL, NULL, NULL, NULL, 395000.00, 6.1500, NULL, NULL, 2450.00, 'monthly', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, true, NULL, NULL, '6e7ac885-bf77-40d9-bb9a-7a827827bf66', '33272370-cb48-31cd-5986-add8755d6842');


--
-- Data for Name: fact_find_property_loan_ownership; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_property_loan_ownership (id, property_loan_id, entity_id, ownership_percentage) VALUES ('b1d6e5da-ceff-5eef-8c93-8743a22f1b15', '194ee2f0-d2f6-5cea-b477-4964c6586ca3', '4a692464-d076-5c32-b162-63dcff4268f8', 50.00);
INSERT INTO public.fact_find_property_loan_ownership (id, property_loan_id, entity_id, ownership_percentage) VALUES ('144dcde1-7560-58bd-b544-7b715f4af583', '194ee2f0-d2f6-5cea-b477-4964c6586ca3', 'f5c5e9a6-2d1c-5e46-b2a1-46e684e46995', 50.00);
INSERT INTO public.fact_find_property_loan_ownership (id, property_loan_id, entity_id, ownership_percentage) VALUES ('67b60835-9db3-510e-88b6-c8c3aeb504e0', 'ab71494c-fbaf-5a7e-9052-a93beb6fd1ef', '4a692464-d076-5c32-b162-63dcff4268f8', 100.00);
INSERT INTO public.fact_find_property_loan_ownership (id, property_loan_id, entity_id, ownership_percentage) VALUES ('b2fcae30-4142-bf48-9962-ef3d8ac9ad75', '64a4a13b-f4db-1694-2c73-c8dad8c0390c', '21340348-85a1-c72f-bdf1-0860c21d4b54', 50.00);
INSERT INTO public.fact_find_property_loan_ownership (id, property_loan_id, entity_id, ownership_percentage) VALUES ('fe07a2a5-bc37-f82c-33fa-1e62b25c390e', '64a4a13b-f4db-1694-2c73-c8dad8c0390c', '928618c6-fbe9-cefb-b909-8749139aba74', 50.00);
INSERT INTO public.fact_find_property_loan_ownership (id, property_loan_id, entity_id, ownership_percentage) VALUES ('76dc8ffd-0659-8a6d-1d2e-a56b0593323d', '5d022f63-ac97-aad7-2cc4-8908079f2bf2', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);
INSERT INTO public.fact_find_property_loan_ownership (id, property_loan_id, entity_id, ownership_percentage) VALUES ('f4af9b8f-7418-431e-b829-70cb88e59c5e', '5ae56d71-6715-42d1-89c3-3432bbe28dfe', '21340348-85a1-c72f-bdf1-0860c21d4b54', 50.00);
INSERT INTO public.fact_find_property_loan_ownership (id, property_loan_id, entity_id, ownership_percentage) VALUES ('acd468e8-8562-4f71-9a2d-7b7289b2a747', '5ae56d71-6715-42d1-89c3-3432bbe28dfe', '928618c6-fbe9-cefb-b909-8749139aba74', 50.00);
INSERT INTO public.fact_find_property_loan_ownership (id, property_loan_id, entity_id, ownership_percentage) VALUES ('5ac65120-30b6-45d9-9d3c-d111b09d3fb7', '82f2cda5-351b-4e7c-af42-ffa45312e3a5', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);


--
-- Data for Name: fact_find_retirement_asset; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_retirement_asset (id, name, provider_name, product_name, fund_name, account_number, fund_type, account_established_date, eligible_service_date, expiry_date, opening_balance, account_balance, preserved_amount, unrestricted_non_preserved_amount, taxable_amount, tax_free_amount, pension_type, pension_payment_amount, pension_payment_frequency, total_fees, administration_fee_amount, administration_fee_percent, adviser_fee_amount, contribution_fee_percent, exit_withdrawal_fee_amount, exit_withdrawal_fee_percent, nomination_type, nomination_percentage, client_notes, financial_planner_notes, case_id, financial_product_id, legacy_account_balance, holdings_configured) VALUES ('56d6716e-7ded-591b-92cf-e2c7f8afc4b2', 'Account based pension', 'Colonial First State', 'FirstChoice Wholesale Pension', 'FirstChoice', 'CFS-33218', 'Account based pension', '2024-07-01', NULL, NULL, NULL, NULL, NULL, NULL, 510000.00, 130000.00, 'Account based pension', 36000.00, 'annual', 4200.00, 1650.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '04c7db5c-6479-4226-9a74-553b9e2da795', 640000.00, false);
INSERT INTO public.fact_find_retirement_asset (id, name, provider_name, product_name, fund_name, account_number, fund_type, account_established_date, eligible_service_date, expiry_date, opening_balance, account_balance, preserved_amount, unrestricted_non_preserved_amount, taxable_amount, tax_free_amount, pension_type, pension_payment_amount, pension_payment_frequency, total_fees, administration_fee_amount, administration_fee_percent, adviser_fee_amount, contribution_fee_percent, exit_withdrawal_fee_amount, exit_withdrawal_fee_percent, nomination_type, nomination_percentage, client_notes, financial_planner_notes, case_id, financial_product_id, legacy_account_balance, holdings_configured) VALUES ('3631f542-71a1-f412-84e0-60faf7772938', 'Account-based pension', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2b042535-7649-d5fa-1d5a-5aa497ad2cdf', 540000.00, false);
INSERT INTO public.fact_find_retirement_asset (id, name, provider_name, product_name, fund_name, account_number, fund_type, account_established_date, eligible_service_date, expiry_date, opening_balance, account_balance, preserved_amount, unrestricted_non_preserved_amount, taxable_amount, tax_free_amount, pension_type, pension_payment_amount, pension_payment_frequency, total_fees, administration_fee_amount, administration_fee_percent, adviser_fee_amount, contribution_fee_percent, exit_withdrawal_fee_amount, exit_withdrawal_fee_percent, nomination_type, nomination_percentage, client_notes, financial_planner_notes, case_id, financial_product_id, legacy_account_balance, holdings_configured) VALUES ('d53c15ac-bec9-b0a0-2591-519f6a62c1f3', 'Supplementary pension', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'fdf4972c-52e4-15b7-ec09-2d74bbd8783a', 125000.00, false);


--
-- Data for Name: fact_find_retirement_asset_item; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_retirement_asset_item (id, retirement_asset_id, name, fund_option, current_value, allocation_percentage, financial_product_id) VALUES ('3070c83f-8a5c-5bff-bfbe-6b249b4092a9', '56d6716e-7ded-591b-92cf-e2c7f8afc4b2', 'Balanced fund', 'Balanced', 448000.00, 70.0000, NULL);
INSERT INTO public.fact_find_retirement_asset_item (id, retirement_asset_id, name, fund_option, current_value, allocation_percentage, financial_product_id) VALUES ('0d90b7e4-e60c-50a0-af31-86efae2378bf', '56d6716e-7ded-591b-92cf-e2c7f8afc4b2', 'Cash option', 'Cash', 192000.00, 30.0000, NULL);
INSERT INTO public.fact_find_retirement_asset_item (id, retirement_asset_id, name, fund_option, current_value, allocation_percentage, financial_product_id) VALUES ('132110cb-ccd4-4271-29e6-5cf7f869db5e', '3631f542-71a1-f412-84e0-60faf7772938', 'Balanced Opportunities Fund', NULL, 378000.00, 70.0000, 'e29fb477-c8e2-14db-e922-863c434ffa82');
INSERT INTO public.fact_find_retirement_asset_item (id, retirement_asset_id, name, fund_option, current_value, allocation_percentage, financial_product_id) VALUES ('c50cb314-0c20-183d-62ba-a15d76549202', '3631f542-71a1-f412-84e0-60faf7772938', 'Australian Equity Index', NULL, 162000.00, 30.0000, '9fd2e96c-2fff-7e85-cee9-3b62a2c78d2b');


--
-- Data for Name: fact_find_retirement_asset_ownership; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_retirement_asset_ownership (id, retirement_asset_id, entity_id, ownership_percentage) VALUES ('974300a0-fff8-5416-8469-961017d2916f', '56d6716e-7ded-591b-92cf-e2c7f8afc4b2', 'c4406eb7-c031-5f29-ab93-beea11e18887', 100.00);
INSERT INTO public.fact_find_retirement_asset_ownership (id, retirement_asset_id, entity_id, ownership_percentage) VALUES ('8d1a47df-2c05-9d39-602b-45f92d1367ef', '3631f542-71a1-f412-84e0-60faf7772938', 'e5a1a5da-551a-79fd-6753-e37c8f4df498', 100.00);
INSERT INTO public.fact_find_retirement_asset_ownership (id, retirement_asset_id, entity_id, ownership_percentage) VALUES ('3b395171-1538-f64b-43df-9d923ec46d59', 'd53c15ac-bec9-b0a0-2591-519f6a62c1f3', 'e5a1a5da-551a-79fd-6753-e37c8f4df498', 100.00);


--
-- Data for Name: fact_find_retirement_income; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_retirement_income (id, name, income_type, income_frequency, income_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('3b6b2a9e-d446-5034-ade7-1b4e8a4b3e6a', 'Account-based pension', 'Account-based pension', 'Monthly', 2200.00, false, NULL, NULL, NULL);
INSERT INTO public.fact_find_retirement_income (id, name, income_type, income_frequency, income_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('3e52ad22-6a90-53d3-8fe2-08c046dd9a0c', 'Lifetime annuity', 'Annuity', 'Monthly', 1450.00, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_retirement_income (id, name, income_type, income_frequency, income_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('b5d870f6-7a6b-5f42-84c8-f56bf7641a6b', 'Transition to retirement', 'Superannuation pension', 'Monthly', 1800.00, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_retirement_income (id, name, income_type, income_frequency, income_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('6cfc44f5-cd77-508e-b8a0-e780f2881d53', 'Superannuation pension', 'Superannuation pension', 'Fortnightly', 900.00, true, 50.00, 'Annual drawdown review', NULL);
INSERT INTO public.fact_find_retirement_income (id, name, income_type, income_frequency, income_amount, income_change_flag, income_change_amount, income_change_reason, case_id) VALUES ('164a2914-a8a1-95e4-9fbb-ea2eba1ad6a4', 'Annual pension drawdown', NULL, NULL, 32400.00, NULL, NULL, NULL, NULL);


--
-- Data for Name: fact_find_retirement_income_ownership; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_retirement_income_ownership (id, retirement_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('b50027e8-3d0d-5a02-b059-bc67f4eeeadf', '3b6b2a9e-d446-5034-ade7-1b4e8a4b3e6a', 'b15a9373-b775-5211-afbf-1bceea904a95', 100.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_retirement_income_ownership (id, retirement_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('6282e376-3358-564e-a078-f311ead89809', '3e52ad22-6a90-53d3-8fe2-08c046dd9a0c', 'a97799ee-e702-5031-ad8f-b80d762cec5a', 100.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_retirement_income_ownership (id, retirement_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('05afd229-df66-5e1f-b7f4-4bf2845ed92f', 'b5d870f6-7a6b-5f42-84c8-f56bf7641a6b', 'ea87fa5d-abe4-5a46-b31e-d036cc2abc8a', 100.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_retirement_income_ownership (id, retirement_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('30ce9c3a-b34b-546e-8290-48a46fba8d2f', '6cfc44f5-cd77-508e-b8a0-e780f2881d53', 'f9438f7c-a8e5-5839-8673-057ba714d3a0', 100.00, '2026-09-23 04:01:39.350679+00', '2026-09-23 04:01:39.350679+00');
INSERT INTO public.fact_find_retirement_income_ownership (id, retirement_income_id, entity_id, ownership_percentage, created_at, updated_at) VALUES ('aa12166c-c806-b0db-a738-76ace1c8bd41', '164a2914-a8a1-95e4-9fbb-ea2eba1ad6a4', 'e5a1a5da-551a-79fd-6753-e37c8f4df498', 100.00, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00');


--
-- Data for Name: fact_find_superannuation; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: fact_find_superannuation_item; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: fact_find_superannuation_ownership; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: fact_find_vehicle; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_vehicle (id, name, make, model, purchase_date, purchase_price, current_market_value, estimated_annual_outgoings, client_notes, financial_planner_notes, case_id) VALUES ('413799e1-3464-54aa-b1ca-d74f9cd5b296', 'Family car', 'BMW', 'X3 xDrive30i', '2023-05-20', 92000.00, 68000.00, 6200.00, NULL, NULL, NULL);
INSERT INTO public.fact_find_vehicle (id, name, make, model, purchase_date, purchase_price, current_market_value, estimated_annual_outgoings, client_notes, financial_planner_notes, case_id) VALUES ('1c16b373-47df-53d7-9a00-8617b26a4d9d', 'Second car', 'Toyota', 'Corolla Hybrid', '2021-11-10', 36000.00, 28500.00, 3200.00, NULL, NULL, NULL);
INSERT INTO public.fact_find_vehicle (id, name, make, model, purchase_date, purchase_price, current_market_value, estimated_annual_outgoings, client_notes, financial_planner_notes, case_id) VALUES ('0e4546cb-374a-4d31-2308-c95572cdeb37', 'Family hybrid SUV', NULL, NULL, NULL, NULL, 38000.00, NULL, NULL, NULL, NULL);
INSERT INTO public.fact_find_vehicle (id, name, make, model, purchase_date, purchase_price, current_market_value, estimated_annual_outgoings, client_notes, financial_planner_notes, case_id) VALUES ('b921f0e6-b660-4d06-ab63-7f8f9fe19177', 'Family hybrid SUV', NULL, NULL, NULL, NULL, 38000.00, NULL, NULL, NULL, '6e7ac885-bf77-40d9-bb9a-7a827827bf66');


--
-- Data for Name: fact_find_vehicle_loan; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_vehicle_loan (id, name, provider, product_name, loan_type, establishment_date, original_loan_amount, current_balance, current_interest_rate, original_loan_term, remaining_loan_term, repayment_amount, repayment_frequency, redraw_amount, redraw_fee, account_fee, monthly_fee, withdrawal_fee, exit_fee, other_fee, guarantor, tax_deductible, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('d00bdf0d-1ee2-54ad-a198-0068662abbca', 'BMW finance', 'BMW Financial Services', 'Vehicle Finance', 'Secured', '2023-05-20', 60000.00, 31500.00, 7.1000, '5 years', '1.7 years', 1180.00, 'monthly', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '40cb3981-f7b1-4f10-835f-3a595fcf4fd7');
INSERT INTO public.fact_find_vehicle_loan (id, name, provider, product_name, loan_type, establishment_date, original_loan_amount, current_balance, current_interest_rate, original_loan_term, remaining_loan_term, repayment_amount, repayment_frequency, redraw_amount, redraw_fee, account_fee, monthly_fee, withdrawal_fee, exit_fee, other_fee, guarantor, tax_deductible, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('a3e10e50-e567-5506-886d-6bc937f7b0c2', 'Hybrid SUV finance', NULL, NULL, NULL, NULL, NULL, 18000.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '446caad3-e0c0-27f5-c197-9674c3ef3e59');
INSERT INTO public.fact_find_vehicle_loan (id, name, provider, product_name, loan_type, establishment_date, original_loan_amount, current_balance, current_interest_rate, original_loan_term, remaining_loan_term, repayment_amount, repayment_frequency, redraw_amount, redraw_fee, account_fee, monthly_fee, withdrawal_fee, exit_fee, other_fee, guarantor, tax_deductible, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('9fdcfa79-174d-143c-0387-408172e37e09', 'Utility vehicle finance', NULL, NULL, NULL, NULL, NULL, 31000.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '446caad3-e0c0-27f5-c197-9674c3ef3e59');
INSERT INTO public.fact_find_vehicle_loan (id, name, provider, product_name, loan_type, establishment_date, original_loan_amount, current_balance, current_interest_rate, original_loan_term, remaining_loan_term, repayment_amount, repayment_frequency, redraw_amount, redraw_fee, account_fee, monthly_fee, withdrawal_fee, exit_fee, other_fee, guarantor, tax_deductible, client_notes, financial_planner_notes, case_id, financial_product_id) VALUES ('ed2e2ed0-5b43-46c5-8b18-48f79626762f', 'Hybrid SUV finance', NULL, NULL, NULL, NULL, NULL, 18000.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '6e7ac885-bf77-40d9-bb9a-7a827827bf66', '446caad3-e0c0-27f5-c197-9674c3ef3e59');


--
-- Data for Name: fact_find_vehicle_loan_ownership; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_vehicle_loan_ownership (id, vehicle_loan_id, entity_id, ownership_percentage) VALUES ('b70df548-29d5-511b-9dd3-3dfe5203b201', 'd00bdf0d-1ee2-54ad-a198-0068662abbca', '4a692464-d076-5c32-b162-63dcff4268f8', 50.00);
INSERT INTO public.fact_find_vehicle_loan_ownership (id, vehicle_loan_id, entity_id, ownership_percentage) VALUES ('d74ac5d3-8097-5e5b-9e26-f094d4c6add7', 'd00bdf0d-1ee2-54ad-a198-0068662abbca', 'f5c5e9a6-2d1c-5e46-b2a1-46e684e46995', 50.00);
INSERT INTO public.fact_find_vehicle_loan_ownership (id, vehicle_loan_id, entity_id, ownership_percentage) VALUES ('dc544e03-08ee-a54f-6f71-8b92b3364e3d', 'a3e10e50-e567-5506-886d-6bc937f7b0c2', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);
INSERT INTO public.fact_find_vehicle_loan_ownership (id, vehicle_loan_id, entity_id, ownership_percentage) VALUES ('3b167687-06fc-fb94-d022-66c1a956af5d', '9fdcfa79-174d-143c-0387-408172e37e09', 'ddbc9aa9-d048-17b2-5335-9682d9601396', 100.00);
INSERT INTO public.fact_find_vehicle_loan_ownership (id, vehicle_loan_id, entity_id, ownership_percentage) VALUES ('50cec88e-91b1-4f32-a33a-88231bf85fc2', 'ed2e2ed0-5b43-46c5-8b18-48f79626762f', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);


--
-- Data for Name: fact_find_vehicle_ownership; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.fact_find_vehicle_ownership (id, vehicle_id, entity_id, ownership_percentage) VALUES ('5b732463-b02d-589d-8376-f7d2e2208e0a', '413799e1-3464-54aa-b1ca-d74f9cd5b296', '4a692464-d076-5c32-b162-63dcff4268f8', 50.00);
INSERT INTO public.fact_find_vehicle_ownership (id, vehicle_id, entity_id, ownership_percentage) VALUES ('fc28ed14-39bd-5a79-b319-d65868c14e42', '413799e1-3464-54aa-b1ca-d74f9cd5b296', 'f5c5e9a6-2d1c-5e46-b2a1-46e684e46995', 50.00);
INSERT INTO public.fact_find_vehicle_ownership (id, vehicle_id, entity_id, ownership_percentage) VALUES ('9d6859c0-17d7-5e50-877d-94fc23035498', '1c16b373-47df-53d7-9a00-8617b26a4d9d', 'f5c5e9a6-2d1c-5e46-b2a1-46e684e46995', 100.00);
INSERT INTO public.fact_find_vehicle_ownership (id, vehicle_id, entity_id, ownership_percentage) VALUES ('d54029ec-d629-154d-3d27-87670024e2b9', '0e4546cb-374a-4d31-2308-c95572cdeb37', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);
INSERT INTO public.fact_find_vehicle_ownership (id, vehicle_id, entity_id, ownership_percentage) VALUES ('9b132fcb-291c-4353-93c2-e26b817ec85c', 'b921f0e6-b660-4d06-ab63-7f8f9fe19177', '21340348-85a1-c72f-bdf1-0860c21d4b54', 100.00);


--
-- Data for Name: financial_planner; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.financial_planner (id, first_name, last_name, business_unit_id, email, phone, adviser_number, asic_adviser_number, is_active, created_at, updated_at, job_title) VALUES ('834dc56d-7ac9-4c1a-bb47-4030aaecbebb', 'Unidentified', 'adviser', '7e841a1e-f7fe-4bfd-b24e-4f86c7a06ff4', NULL, NULL, 'Legacy ID: 834dc56d-7ac9-4c1a-bb47-4030aaecbebb', NULL, false, '2026-09-28 06:27:02.116661+00', '2026-09-28 06:27:02.116661+00', NULL);
INSERT INTO public.financial_planner (id, first_name, last_name, business_unit_id, email, phone, adviser_number, asic_adviser_number, is_active, created_at, updated_at, job_title) VALUES ('dfa5a8f7-56c8-97d2-dcf0-39c2da5b0d1d', 'Olivia', 'Chen', '16788c78-8160-7a75-53f5-8abf8e9fa75e', 'olivia.chen@sydney.example.invalid', '0400 000 001', NULL, NULL, true, '2026-09-01 00:00:00+00', '2026-09-01 00:00:00+00', 'Principal Adviser');
INSERT INTO public.financial_planner (id, first_name, last_name, business_unit_id, email, phone, adviser_number, asic_adviser_number, is_active, created_at, updated_at, job_title) VALUES ('bd49d568-8006-e2c8-3520-9afeb4a7a044', 'Ethan', 'Clarke', '16788c78-8160-7a75-53f5-8abf8e9fa75e', 'ethan.clarke@sydney.example.invalid', '0400 000 002', NULL, NULL, true, '2026-09-01 00:00:00+00', '2026-09-01 00:00:00+00', 'Senior Financial Planner');
INSERT INTO public.financial_planner (id, first_name, last_name, business_unit_id, email, phone, adviser_number, asic_adviser_number, is_active, created_at, updated_at, job_title) VALUES ('14588188-3023-8a55-2fcf-8935eafe4ec1', 'Sophie', 'Patel', '16788c78-8160-7a75-53f5-8abf8e9fa75e', 'sophie.patel@sydney.example.invalid', '0400 000 003', NULL, NULL, true, '2026-09-01 00:00:00+00', '2026-09-01 00:00:00+00', 'Associate Adviser');
INSERT INTO public.financial_planner (id, first_name, last_name, business_unit_id, email, phone, adviser_number, asic_adviser_number, is_active, created_at, updated_at, job_title) VALUES ('14701153-ca74-f338-6439-4bcefdef14aa', 'James', 'Nguyen', '22a87309-286e-5b1f-7046-bed985bfde53', 'james.nguyen@hills.example.invalid', '0400 000 004', NULL, NULL, true, '2026-09-01 00:00:00+00', '2026-09-01 00:00:00+00', 'Senior Financial Adviser');
INSERT INTO public.financial_planner (id, first_name, last_name, business_unit_id, email, phone, adviser_number, asic_adviser_number, is_active, created_at, updated_at, job_title) VALUES ('ed5cd07b-3c4f-e880-4f51-ed7981b9781d', 'Isla', 'Mitchell', '22a87309-286e-5b1f-7046-bed985bfde53', 'isla.mitchell@hills.example.invalid', '0400 000 005', NULL, NULL, true, '2026-09-01 00:00:00+00', '2026-09-01 00:00:00+00', 'Financial Planner');
INSERT INTO public.financial_planner (id, first_name, last_name, business_unit_id, email, phone, adviser_number, asic_adviser_number, is_active, created_at, updated_at, job_title) VALUES ('a5924ce2-e699-a1d3-d157-9fc54d11ce4b', 'William', 'Shah', '22a87309-286e-5b1f-7046-bed985bfde53', 'william.shah@hills.example.invalid', '0400 000 006', NULL, NULL, true, '2026-09-01 00:00:00+00', '2026-09-01 00:00:00+00', 'Associate Adviser');
INSERT INTO public.financial_planner (id, first_name, last_name, business_unit_id, email, phone, adviser_number, asic_adviser_number, is_active, created_at, updated_at, job_title) VALUES ('4017ffe1-b404-db14-18d1-e84fa4fde325', 'Grace', 'Wilson', '1a3bba02-8053-aa10-967f-2a2c561bb7bc', 'grace.wilson@melbourne.example.invalid', '0400 000 007', NULL, NULL, true, '2026-09-01 00:00:00+00', '2026-09-01 00:00:00+00', 'Principal Adviser');
INSERT INTO public.financial_planner (id, first_name, last_name, business_unit_id, email, phone, adviser_number, asic_adviser_number, is_active, created_at, updated_at, job_title) VALUES ('5e6c9ee8-3e7d-43ca-dbd6-75a41c90d78b', 'Leo', 'Tan', '1a3bba02-8053-aa10-967f-2a2c561bb7bc', 'leo.tan@melbourne.example.invalid', '0400 000 008', NULL, NULL, true, '2026-09-01 00:00:00+00', '2026-09-01 00:00:00+00', 'Financial Adviser');
INSERT INTO public.financial_planner (id, first_name, last_name, business_unit_id, email, phone, adviser_number, asic_adviser_number, is_active, created_at, updated_at, job_title) VALUES ('94a2d4e1-a05d-f1d4-49f9-e62f58e317fc', 'Ava', 'Reid', '1a3bba02-8053-aa10-967f-2a2c561bb7bc', 'ava.reid@melbourne.example.invalid', '0400 000 009', NULL, NULL, true, '2026-09-01 00:00:00+00', '2026-09-01 00:00:00+00', 'Associate Adviser');
INSERT INTO public.financial_planner (id, first_name, last_name, business_unit_id, email, phone, adviser_number, asic_adviser_number, is_active, created_at, updated_at, job_title) VALUES ('74f7b4ff-015c-602f-0992-eb94ae05723d', 'Henry', 'Brooks', '9b1d9b94-6eba-2378-f765-752aeb2afed4', 'henry.brooks@brisbane.example.invalid', '0400 000 010', NULL, NULL, true, '2026-09-01 00:00:00+00', '2026-09-01 00:00:00+00', 'Senior Financial Planner');
INSERT INTO public.financial_planner (id, first_name, last_name, business_unit_id, email, phone, adviser_number, asic_adviser_number, is_active, created_at, updated_at, job_title) VALUES ('ea9d1192-ebcb-909e-8f9e-b56ff0103d43', 'Mia', 'Singh', '9b1d9b94-6eba-2378-f765-752aeb2afed4', 'mia.singh@brisbane.example.invalid', '0400 000 011', NULL, NULL, true, '2026-09-01 00:00:00+00', '2026-09-01 00:00:00+00', 'Financial Adviser');
INSERT INTO public.financial_planner (id, first_name, last_name, business_unit_id, email, phone, adviser_number, asic_adviser_number, is_active, created_at, updated_at, job_title) VALUES ('84c2d8a4-cce1-a3c0-981c-92092ece7572', 'Ruby', 'Lawson', '3a1bde9b-e983-2088-4193-ab580932dfdf', 'ruby.lawson@boutique.example.invalid', '0400 000 012', NULL, NULL, true, '2026-09-01 00:00:00+00', '2026-09-01 00:00:00+00', 'Principal Adviser');


--
-- Data for Name: financial_product; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('5851d76e-e74e-4065-b12f-1b70060cf247', 'OLD', 'OLD', 'investment', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:21:50.143452+00', '2026-09-26 09:21:50.143452+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('98981ff1-2611-43c6-b292-a56d1209e250', 'OLD', 'OLD', 'cash_account', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:21:50.143452+00', '2026-09-26 09:21:50.143452+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('be1681ce-e260-471a-bdfd-41a484599c29', 'OLD', 'OLD', 'term_deposit', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:21:50.143452+00', '2026-09-26 09:21:50.143452+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('3dd3a80a-3751-4989-b2ae-b955384e5ce6', 'OLD', 'OLD', 'insurance', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:21:50.143452+00', '2026-09-26 09:21:50.143452+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('f8eccf88-310d-4043-86fd-fb755a081169', 'OLD', 'OLD', 'personal_loan', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:21:50.143452+00', '2026-09-26 09:21:50.143452+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('5942b28d-ff54-4c5b-8e5c-d22f37901061', 'OLD', 'OLD', 'insurance', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:21:50.143452+00', '2026-09-26 09:21:50.143452+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('40cb3981-f7b1-4f10-835f-3a595fcf4fd7', 'OLD', 'OLD', 'vehicle_loan', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:21:50.143452+00', '2026-09-26 09:21:50.143452+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('a9118796-df4b-4930-a991-a3fdc5a7a2f6', 'OLD', 'OLD', 'credit_card', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:21:50.143452+00', '2026-09-26 09:21:50.143452+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('17a1ed61-fdd5-4600-8b13-d4c92c72d7bd', 'OLD', 'OLD', 'home_loan', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:21:50.143452+00', '2026-09-26 09:21:50.143452+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('1502a33c-6d38-43bc-b9a9-cc466e9ffb52', 'OLD', 'OLD', 'superannuation', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:21:50.143452+00', '2026-09-26 09:21:50.143452+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('4754f7db-0519-496c-8a33-9a363b999dad', 'OLD', 'OLD', 'cash_account', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:21:50.143452+00', '2026-09-26 09:21:50.143452+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('bbcfbe50-3a44-486e-952d-7f939401d3f7', 'OLD', 'OLD', 'cash_account', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:21:50.143452+00', '2026-09-26 09:21:50.143452+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('85387aef-f324-4643-bb9a-245b2f76b1e6', 'OLD', 'OLD', 'home_loan', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:21:50.143452+00', '2026-09-26 09:21:50.143452+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('04c7db5c-6479-4226-9a74-553b9e2da795', 'OLD', 'OLD', 'pension', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:21:50.143452+00', '2026-09-26 09:21:50.143452+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('8d651a3d-2225-40b2-b824-55753ebf130e', 'OLD', 'OLD', 'superannuation', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:21:50.143452+00', '2026-09-26 09:21:50.143452+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('70f35aaa-57fd-4d14-9ce3-269bf7192c32', 'OLD', 'OLD', 'credit_card', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:21:50.143452+00', '2026-09-26 09:21:50.143452+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('30214bb9-671c-4788-bfb5-669560c02849', 'OLD', 'OLD', 'platform', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:21:50.143452+00', '2026-09-26 09:21:50.143452+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('92950467-1925-491e-ad83-2f34c1ad1107', 'Asgard', 'Asgard Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Asgard.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 524);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('4c51bb4b-b917-a216-34e1-2b69902496e6', 'OLD', 'OLD', 'managed_fund', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('fdf4972c-52e4-15b7-ec09-2d74bbd8783a', 'OLD', 'OLD', 'pension', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('9fd2e96c-2fff-7e85-cee9-3b62a2c78d2b', 'OLD', 'OLD', 'etf', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('e29fb477-c8e2-14db-e922-863c434ffa82', 'OLD', 'OLD', 'managed_fund', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('717fe799-f5ac-2dd7-58eb-76e1e03182c7', 'OLD', 'OLD', 'investment', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('b6f144d8-64bd-83a9-2770-b5bd7162f031', 'OLD', 'OLD', 'credit_card', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('efde9db8-ba62-6817-fef6-56e3e0281935', 'OLD', 'OLD', 'superannuation', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('d940d60f-6c9c-566a-ef31-33c97ec79121', 'OLD', 'OLD', 'transaction_account', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('28a3ef17-5200-3ea8-8cee-d01baf7b7458', 'OLD', 'OLD', 'home_loan', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('ee67655b-8eeb-0e0e-ec3a-0ec33bbbb464', 'OLD', 'OLD', 'personal_loan', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('446caad3-e0c0-27f5-c197-9674c3ef3e59', 'OLD', 'OLD', 'vehicle_loan', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('2b042535-7649-d5fa-1d5a-5aa497ad2cdf', 'OLD', 'OLD', 'pension', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('0236248f-4b45-6c0d-c7a4-9ed1079c2a39', 'OLD', 'OLD', 'superannuation', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('f51e3db9-fb17-9dba-6213-590dec43a8db', 'OLD', 'OLD', 'credit_card', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('33272370-cb48-31cd-5986-add8755d6842', 'OLD', 'OLD', 'investment_loan', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('3052af08-4582-5d73-38a9-3b9a2e39ba9b', 'OLD', 'OLD', 'superannuation', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('8bc8398a-66f6-cf50-aabf-8b3123d197f9', 'OLD', 'OLD', 'etf', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('f116d744-f26b-2619-8ce0-51144c12c4d4', 'OLD', 'OLD', 'share', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('f9731a25-cb1e-a118-c126-b0e888297dd8', 'OLD', 'OLD', 'home_loan', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('94b13130-75fc-1e89-e746-6fe3e104ad5f', 'OLD', 'OLD', 'platform', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('548f3148-b2df-b9c8-370d-915619708fbd', 'OLD', 'OLD', 'savings_account', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('c1c665d8-a0ec-8abb-49ba-992a071c094d', 'OLD', 'OLD', 'cash_account', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('149a105f-ee27-77bc-edfe-2ebbae3ae72d', 'OLD', 'OLD', 'savings_account', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('a260e9f8-66a9-e649-6c7b-8794e21ae094', 'OLD', 'OLD', 'insurance', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('e0add750-7688-8bc2-f47e-8f390b0a70a8', 'OLD', 'OLD', 'term_deposit', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('b49e272e-56a3-a78c-5816-da63e8aa8c2d', 'OLD', 'OLD', 'insurance', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('9fab45a3-71ae-9dca-fd04-9cf1e0ebe046', 'OLD', 'OLD', 'term_deposit', NULL, NULL, NULL, NULL, false, 'OLD', NULL, '2026-09-26 09:26:41.563295+00', '2026-09-26 09:26:41.563295+00', NULL);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('6f675831-ba28-43cb-8377-53a5faa21bb1', 'Pearler', 'Pearler Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Pearler.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 589);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('237a4294-61fe-4790-b3e9-177d1ed07413', 'OnePath / Insignia Financial', 'OnePath OneAnswer Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by OnePath / Insignia Financial.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 152);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('5a701e24-f97b-41a0-9424-bab7bd5fe9a6', 'Generic / Overseas pension', 'UK Pension', 'pension', NULL, NULL, NULL, 'Generic record for a United Kingdom pension arrangement.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 574);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('0f26d275-8fce-4aa9-b550-a0d51c79641a', 'YourChoice / OneVue', 'YourChoice Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by YourChoice / OneVue.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 533);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('376ea7e4-a6af-4085-851d-f6bff851fe5c', 'Macquarie', 'Macquarie Online Trading', 'platform', NULL, NULL, NULL, 'Investment/trading platform offered by Macquarie.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 503);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('98cb61bd-0bb3-4f84-9540-9d55b4c7bff0', 'Commonwealth Bank', 'Commonwealth Essential Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Commonwealth Bank.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 495);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('33039aa1-9d6f-4ab2-bf25-8dc1434e93a3', 'ElectricSuper', 'ElectricSuper Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by ElectricSuper.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 114);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('da40f088-697a-4bb8-837b-d92ba8867738', 'IOOF / Insignia Financial', 'IOOF WealthBuilder', 'investment', NULL, NULL, NULL, 'General investment product offered by IOOF / Insignia Financial.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 275);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('599c18b1-f2fc-4e81-9daf-b92e2a87a4ef', 'Rest', 'REST Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Rest.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 12);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('849073a0-f62d-44dd-8aff-7efe029920ba', 'Stake', 'Stake Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Stake.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 573);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('14dbfbc0-cc02-424e-94d0-4b9c989bc450', 'GESB', 'GESB Super Transition To Retirement', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by GESB.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 51);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('ab4690cc-139f-45ad-bde0-ca197d704885', 'Colonial First State', 'CFS FirstChoice Employer Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Colonial First State.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 209);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('c58ad72c-32f7-4c0f-86aa-93fc2dd0ebc4', 'CareSuper', 'CareSuper Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by CareSuper.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 22);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('9e5d58f6-08b6-41b3-9939-b56ffc440852', 'legalsuper', 'legalsuper Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by legalsuper.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 56);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('8463af49-dd4a-4a2e-8968-e90ab5632430', 'Active Super', 'Active Super Income Streams', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Active Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 59);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('ab13a0d5-733f-4216-a7b7-752ba0706be7', 'SelfWealth', 'SelfWealth', 'platform', NULL, NULL, NULL, 'Investment/trading platform offered by SelfWealth.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 521);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('10fac042-7ab2-4ad1-9f01-79d95bf958ea', 'Oracle Investment Management', 'Oracle Managed Account Series 1', 'platform', NULL, NULL, NULL, 'Managed-account/SMA investment platform offered by Oracle Investment Management.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 535);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('f1e281cc-2b2f-44a9-9770-2178ea7808f7', 'BT', 'BT SuperWrap Open - Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by BT.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 200);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('16a92348-b1be-49eb-893e-e198bf997657', 'Vanguard', 'Vanguard Super SpendSmart', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Vanguard.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 544);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('2609f9ef-f898-468a-9f05-803f9d272d2d', 'Asgard', 'Asgard Elements - Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Asgard.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 157);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('ba5c3b73-8aa8-467d-952f-467b9898a8de', 'Platformplus', 'Platformplus Super WRAP - Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Platformplus.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 483);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('0fcdf72a-5749-41c8-88aa-a88b7036e5f4', 'Praemium', 'Praemium SMA', 'platform', NULL, NULL, NULL, 'Managed-account/SMA investment platform offered by Praemium.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 373);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('c57704ee-1a91-417c-a487-9fd8ca37901c', 'MLC / Insignia Financial', 'MLC Masterkey Unit Trust', 'managed_fund', NULL, NULL, NULL, 'Managed investment fund product or fund range offered by MLC / Insignia Financial.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 309);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('c2c02535-03c8-45a3-8ce8-6bcacdb1248b', 'BT', 'Asset Administrator Investments', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by BT.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 184);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('db9b7885-fb6a-4263-92be-e00e3fb7c611', 'BT', 'BT Select Portfolio SuperWrap - Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by BT.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 192);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('24013d4c-788a-498b-9c99-0c66cd4b750c', 'DASH', 'DASH Super Simplifier', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by DASH.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 461);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('6478f8f6-cb6a-4e37-ba4d-d1d90c208adb', 'Qantas Super', 'Qantas Group Super Plan', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Qantas Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 76);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('360abed2-5f49-477f-bf4d-7d0300361523', 'Asgard', 'Asgard Open eWRAP Investment', 'platform', NULL, NULL, NULL, 'Wrap investment administration platform offered by Asgard.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 166);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('8c89506a-1d7c-49b9-bed7-8ddd5c4a5aee', 'WealthTrac', 'WealthTrac Portfolio Service', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by WealthTrac.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 407);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('27501625-9656-41dd-aa78-be2bea3b9bd4', 'Future Super', 'Future Super Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Future Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 452);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('a911414d-5d95-44a8-9806-72fddbe6efd8', 'OnePath / Insignia Financial', 'OneAnswer Frontier Personal Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by OnePath / Insignia Financial.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 343);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('57a1fcb7-5413-4f4a-9350-11182b745ab1', 'Portfoliofocus', 'Portfoliofocus - Premium Investment Service Series 2', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Portfoliofocus.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 494);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('ab61c804-6363-4553-8159-dfd41b54076b', 'Platformplus', 'Platformplus Super WRAP', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Platformplus.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 481);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('ea1b3329-b265-4706-af2d-b5108dc23d83', 'BT', 'BT Wrap Investment', 'platform', NULL, NULL, NULL, 'Wrap investment administration platform offered by BT.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 445);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('657dfcdd-da7d-4826-97c4-2be57326788b', 'HUB24', 'HUB24 Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by HUB24.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 246);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('a96851a8-b6f2-4b0e-aee5-425bcb1d8e3f', 'Macquarie', 'Macquarie Investment Consolidator II', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Macquarie.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 281);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('26b13b1d-30a8-4e72-8ae8-cba55a9a53ad', 'Australian Ethical', 'Australian Ethical Super Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Australian Ethical.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 110);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('cc070289-7484-4a7e-9160-598d892b27b5', 'Self-managed / client managed', 'Self Managed Super Fund (Pension)', 'pension', NULL, NULL, NULL, 'Generic self-managed super fund record for pension-phase benefits.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 587);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('6f237ab2-b895-41ff-9a07-7f4e9a401a13', 'Westpac', 'Westpac Group Plan', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Westpac.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 568);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('11aa34b0-3c58-4564-acb0-ee3014b90176', 'AMP', 'AMP Super Allocated Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by AMP.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 463);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('726d228d-d941-4fdd-8260-cc286d653570', 'Asgard', 'Asgard Open eWRAP Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Asgard.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 168);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('b1144517-46b6-4616-8f3c-321ed7d08d32', 'Loyalty Wealth', 'Loyalty Wealth - Investment', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Loyalty Wealth.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 549);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('c00b328a-d7dd-41ca-9e18-354832a636f3', 'CommSec', 'CommSec', 'platform', NULL, NULL, NULL, 'Investment/trading platform offered by CommSec.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 557);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('607f8e22-fe63-4cf0-8d77-c013eee62438', 'smartMonday', 'smartMonday PRIME', 'platform', NULL, NULL, NULL, 'Managed-account/SMA investment platform offered by smartMonday.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 81);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('b14013a9-592c-4ddd-be8a-1f4e734a863e', 'Cbus Super', 'CBUS TTR', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Cbus Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 28);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('5fc85b94-6128-4f5b-8f8b-7e17fefc48bb', 'Professional Super', 'Professional Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Professional Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 560);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('471967bd-65de-4cca-bfa6-ce5dbcc39080', 'Rhythm', 'Rhythm Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Rhythm.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 507);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('1841e54b-4c45-4f1d-88e1-689467417f98', 'Spirit Super', 'Spirit Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Spirit Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 447);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('a0d7802b-f391-4736-b09b-3ca12d55757c', 'Desktop Broker', 'Desktop Broker', 'platform', NULL, NULL, NULL, 'Investment/trading platform offered by Desktop Broker.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 583);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('10aea87b-2d24-4ef4-968e-d2787a5db18b', 'Hostplus', 'HostPlus Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Hostplus.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 53);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('e6e57389-5c28-4b46-b6a6-5d909d22d9f8', 'Netwealth', 'Netwealth Super Accelerator Plus', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Netwealth.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 333);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('c3e28591-5799-4bce-9670-180c70f5b0ce', 'Netwealth', 'Netwealth Wealth Accelerator Plus', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Netwealth.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 334);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('5209d824-0191-480f-bd29-cb06c16bf341', 'Commonwealth Superannuation Corporation', 'CSCri', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Commonwealth Superannuation Corporation.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 520);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('81b048fb-9bc4-4742-8944-b94679edf727', 'Pearler', 'Pearler ASX Invest', 'platform', NULL, NULL, NULL, 'Investment/trading platform offered by Pearler.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 588);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('21034f61-d992-4027-8ba1-b668fe80d3d9', 'Spaceship', 'Spaceship Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Spaceship.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 126);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('660d07e2-695c-4f23-95ae-2e16d8669254', 'AssetLink', 'AssetLink SuperWrap Personal Super Plan', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by AssetLink.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 169);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('d9048292-0f5c-43d9-a6fa-1cb71d311ae0', 'Equip Super', 'Equip MyFuture', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Equip Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 34);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('a536f17a-3815-4f4a-908c-93a511775cbc', 'Resolution Life', 'Resolution Life Investment Linked Personal Superannuation Plan', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Resolution Life.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 590);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('0c37c41e-a33a-4930-b480-29c0594db8ca', 'ANZ', 'ANZ V2 Plus', 'cash_account', NULL, NULL, NULL, 'Cash management/account product offered by ANZ.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 584);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('8345a467-8735-49e4-a7f1-98648a6b0ec1', 'Netwealth', 'Netwealth Pension Accelerator Plus', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Netwealth.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 336);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('1324432c-bc58-44ce-838c-ad191a76c90f', 'Perpetual', 'Perpetual Private Pension Wrap', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Perpetual.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 357);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('4345f2b2-23f9-46ec-9100-05f5a3c9d011', 'Raiz', 'Raiz Invest Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Raiz.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 585);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('6bf7ddc5-7e3e-4524-9b1d-1a6fba874abf', 'ADF Super', 'ADF Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by ADF Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 487);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('d05fff30-f6c0-42dd-88a5-60f656c714c8', 'Praemium', 'Praemium SMA Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Praemium.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 371);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('866f064b-2492-4ec8-b75c-9b895dd95357', 'Voyage', 'Voyage Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Voyage.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 411);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('592e5db1-700e-433b-89e0-b1d0952764be', 'Asgard', 'Asgard Elements - Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Asgard.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 158);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('c8e39513-1bd2-479f-94bc-c78d873b9c54', 'Grow Wrap', 'Grow Wrap Pension Service', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Grow Wrap.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 241);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('17e42a92-c8fe-4e22-a864-53f051639d3b', 'Resolution Life', 'Resolution Life Guaranteed Super Account', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Resolution Life.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 145);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('98eacb2f-5f9c-4033-a67b-2b4713a14d08', 'Mercer', 'Mercer SmartRetirement Income', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Mercer.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 301);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('e5b70758-5a3f-4a9f-8ade-ed53b132aa63', 'UniSuper', 'UniSuper Defined Benefit', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by UniSuper.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 401);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('7663d62f-8862-4187-a055-7d5b9ff0ec23', 'Verve Super', 'Verve Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Verve Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 592);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('07b1286c-f395-4e5d-b9bb-2ce196b27d76', 'YourChoice / OneVue', 'YourChoice Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by YourChoice / OneVue.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 534);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('46324966-bef0-4ae1-8f44-117a333f1b33', 'MLC / Insignia Financial', 'MLC Masterkey Super Fundamentals', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by MLC / Insignia Financial.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 303);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('01cba075-8d90-4ec2-8140-b4401828020d', 'Pearl', 'Pearl - Investments', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Pearl.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 593);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('808cac1d-ca46-4767-993d-0d84b3546887', 'Perpetual', 'Perpetual Select Investment Funds', 'managed_fund', NULL, NULL, NULL, 'Managed investment fund product or fund range offered by Perpetual.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 352);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('18303e05-0fc6-4409-9bc7-443ced882593', 'BT', 'Asset Administrator Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by BT.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 183);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('218414ec-d5a9-4824-ae65-feee922386fc', 'Generation Life', 'Generation Life FuneralBond', 'investment', NULL, NULL, NULL, 'Investment bond designed to help fund future funeral expenses, offered by Generation Life.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 235);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('b520314c-4fb3-437e-a9ad-b6cfeb372aba', 'Generic / Other', 'Cash Account', 'cash_account', NULL, NULL, NULL, 'Cash management/account product offered by Generic / Other.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 480);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('cee68d33-c707-42d8-add6-822f67defd24', 'Resolution Life', 'RLA Allocated Pension Plan', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Resolution Life.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 559);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('21372421-b47d-4a49-9cda-657ddbc309ff', 'Netwealth', 'Netwealth Super Accelerator Core', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Netwealth.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 441);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('a8c2ee94-aeb3-496c-92e2-cd516704b580', 'Portfolio Administrator', 'Portfolio Administrator SuperWrap', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Portfolio Administrator.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 359);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('c8f96c28-8d2e-450f-8267-b47d2ee68adb', 'Asgard', 'Asgard Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Asgard.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 523);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('d8adc7e2-cf93-41e0-ba88-3e53e5ca26bf', 'IconiQ', 'IconiQ Pension Wrap', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by IconiQ.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 566);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('ee62212e-cb6b-457b-9fe0-427d878d63d3', 'Perpetual', 'Perpetual WealthFocus Investment Advantage', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Perpetual.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 351);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('0a00853e-5ae8-4110-b344-873746528fd2', 'Russell Investments', 'Russell Investments Super Series', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Russell Investments.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 382);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('546fc613-cb5e-420d-97d4-2fbe8c882aa2', 'Colonial First State', 'CFS FirstChoice Wholesale Personal Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Colonial First State.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 211);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('468e0bc8-076d-4a5f-a266-3142be36228c', 'Portfolio Administrator', 'Portfolio Administrator SuperWrap Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Portfolio Administrator.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 360);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('bbb284b3-6b24-42c3-b0ec-0360be678fb2', 'AustralianSuper', 'AustralianSuper Choice Income', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by AustralianSuper.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 18);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('e7474f46-e9f9-450d-8988-581ecc0652ff', 'Praemium', 'Praemium Partner SuperSMA - Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Praemium.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 375);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('2cf81863-1bf0-47ba-a6e2-3a3719628678', 'Hejaz Financial Services', 'Hejaz Islamic Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Hejaz Financial Services.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 530);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('57ed0b23-cec6-4d07-b937-83a06ebd6d04', 'Generation Life', 'Generation Life LifeIncome', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Generation Life.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 488);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('1a28a63d-c60d-41ee-93b1-ae4d10387d94', 'Macquarie', 'Macquarie Investment Manager', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Macquarie.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 292);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('3606e3d0-8e1a-4333-b007-79a8fc8037e7', 'Test / QA', 'ZZ QA Lane6 Platform Name', 'platform', NULL, NULL, NULL, 'QA/test platform record; not a live customer product.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 600);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('e3427439-968e-4026-b401-f05b6579b2fb', 'Raiz', 'Raiz Invest', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Raiz.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 598);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('c2f80cd5-514d-4bda-93fe-30178c603fbd', 'NGS Super', 'NGS Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by NGS Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 71);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('acdf5381-b91f-40bf-b8b1-5baa662f40e3', 'Resource Super', 'Resource Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Resource Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 388);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('f07f5f3e-fe3d-44d7-bf8b-b1d2d978a215', 'Macquarie', 'Macquarie CMA', 'cash_account', NULL, NULL, NULL, 'Cash management/account product offered by Macquarie.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 471);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('41d02d8c-1e41-4a8d-bbb9-a4d83bf65948', 'Centric', 'Centric Investment', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Centric.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 540);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('7d6e8f90-059a-4353-9c18-8f96f05cb6af', 'Betashares', 'Betashares Direct', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Betashares.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 575);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('741b0f3c-9e80-4ff2-9dad-a1c9340bc313', 'Expand / Insignia Financial', 'Expand Extra Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Expand / Insignia Financial.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 273);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('830edf43-6455-4e7f-a859-47e5415bc429', 'Asgard', 'Asgard Investment', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Asgard.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 525);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('021b2d00-c03d-4511-bf1c-fbedcab99e95', 'Insignia Financial', 'Insignia Wrap', 'platform', NULL, NULL, NULL, 'Wrap investment administration platform offered by Insignia Financial.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 251);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('959efe69-2742-4118-8629-dc2ff03e730b', 'Commonwealth Superannuation Corporation', 'PSSAP', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Commonwealth Superannuation Corporation.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 75);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('ad21f1ff-bd3a-4e36-add8-bbf3c41dea1b', 'Self-managed / client managed', 'Self Managed Super Fund (Super)', 'superannuation', NULL, NULL, NULL, 'Generic self-managed super fund record for accumulation-phase superannuation.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 586);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('c1814f4c-bf2a-4a6b-b996-7e2e54c39eae', 'Executive Choice', 'Executive Choice Investments Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Executive Choice.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 554);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('14ba9bff-ff4c-4dab-bc5b-4a6b7debbf55', 'Symetry', 'Symetry Active Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Symetry.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 423);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('2e2b744a-5f1d-4c36-ba48-97bb78473ef6', 'Crescent Wealth', 'Crescent Wealth Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Crescent Wealth.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 426);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('26e68d9b-f1ea-4543-ad4f-806e0347b2a4', 'Allianz Retire+', 'Allianz Retire+', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Allianz Retire+.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 538);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('1d2f379d-fbe5-4742-a053-5fd3822428a1', 'Hejaz Financial Services', 'Hejaz Islamic Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Hejaz Financial Services.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 531);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('91984cbf-c84e-4457-9aea-f2a69de9ee13', 'Freedom of Choice', 'Freedom of Choice Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Freedom of Choice.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 519);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('4270e53c-1656-4018-b32a-7281be60a3e2', 'vMAPs', 'vMAPs Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by vMAPs.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 403);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('22b2fe7a-edf8-4244-a6b2-6caec887b582', 'AMP', 'MyNorth Deferred Lifetime Income', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by AMP.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 505);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('5fdcd389-6309-4824-9c9a-fc64c45a277a', 'UniSuper', 'UniSuper Flexi Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by UniSuper.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 98);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('fa23a157-e6b9-418c-a8b2-c2553d2c3573', 'Rest', 'REST Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Rest.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 381);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('b7523116-f6fe-409d-926e-cee38cab9821', 'Team Super', 'Team Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Team Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 123);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('daecb196-b159-4ea9-810e-0a9d4999419b', 'Challenger', 'Challenger Guaranteed Annuity', 'pension', NULL, NULL, NULL, 'Annuity/retirement-income product offered by Challenger.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 486);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('a50e0cd0-25c5-4ee4-9fdb-d9e3c58911f4', 'GESB', 'GESB Retirement Income Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by GESB.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 48);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('0d56aaee-22af-447a-9511-8dd36b1e73ad', 'ING', 'ING Living Super Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by ING.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 248);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('70df6da1-2f72-4e28-8748-8aa3ba4a761e', 'MLC / Insignia Financial', 'MLC Masterkey Business Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by MLC / Insignia Financial.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 302);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('5fbba945-84c7-4115-8eb6-e3e7179f5113', 'Loyalty Wealth', 'Loyalty Wealth - Superannuation', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Loyalty Wealth.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 547);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('d3a618b1-4d91-4a97-b8d1-c4ffae6e950f', 'Australian Unity', 'Lifeplan Education Bond', 'investment', NULL, NULL, NULL, 'Investment bond/product designed for long-term family or education savings, offered by Australian Unity.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 279);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('2a93533c-592b-46f2-9472-af7df672302c', 'AMP', 'MyNorth Investment', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by AMP.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 330);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('a468a395-dd1c-42fa-b3fa-3336b5ed201c', 'Asgard', 'Asgard Infinity eWRAP Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Asgard.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 165);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('4ac7dfec-d7f7-46f6-a699-783cce08efe1', 'HESTA', 'HESTA Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by HESTA.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 243);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('2a1c4675-9bd6-4fd4-8ec1-0202d9769a3d', 'HUB24', 'HUB24 SMSF', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by HUB24.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 522);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('734a66e4-8ae1-40c8-b707-46994dd64be6', 'Macquarie', 'Macquarie Pension Consolidator II', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Macquarie.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 283);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('347aef2f-a266-4cdc-b214-b86035af0f53', 'Grow Wrap', 'Grow Wrap Super Service', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Grow Wrap.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 240);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('e4939490-7436-413c-9e04-2a7a93b300e9', 'Plum Super', 'Plum Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Plum Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 358);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('364eab41-2c80-4362-8648-5105a78b6eb5', 'Superhero', 'Superhero Super Retirement', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Superhero.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 577);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('35f89501-52c9-4cdd-86a7-15a137e628e6', 'Rhythm', 'Rhythm Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Rhythm.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 508);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('72b931d7-7fd7-4e60-9729-aced56701f77', 'LifeFocus', 'Lifefocus eWrap Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by LifeFocus.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 551);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('f04f2f2a-6508-416e-aa72-df73bc3318a7', 'Australian Ethical', 'Australian Ethical Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Australian Ethical.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 109);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('4cab2edb-ab47-4d0e-824d-fb955b0b9143', 'Symetry', 'Symetry Delegate', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Symetry.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 419);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('433c9a49-f895-4f3b-9074-dcc4628a509c', 'TelstraSuper', 'TelstraSuper RetireAccess', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by TelstraSuper.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 397);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('a4203ba9-7c3a-405f-82d3-e29905d3c461', 'Active Super', 'Active Super Saver', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Active Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 57);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('aa05ec37-83a3-4c44-a34f-88bfc1d0c497', 'ING', 'ING Living Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by ING.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 54);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('40ea91dd-289c-44f8-a6a9-8107364a3d76', 'Australian Money Market', 'Australian Money Market', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Australian Money Market.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 581);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('57466af2-566d-4041-9673-7607c3363500', 'DASH', 'DASH Super Simplifier (Pension)', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by DASH.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 510);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('7d0f9792-b98e-418b-a46a-a9abe62b8d96', 'IOOF / Insignia Financial', 'IOOF Employer Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by IOOF / Insignia Financial.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 257);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('996ffa88-beed-4d78-b5dd-4743173973e1', 'Bell Potter', 'Bell Potter Online', 'platform', NULL, NULL, NULL, 'Investment/trading platform offered by Bell Potter.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 582);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('a2a7798a-cb95-4ccf-96e8-a1ac13b1e750', 'Apex Macro Financial Group', 'AMFG - Investments', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Apex Macro Financial Group.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 562);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('e0472abb-cbef-4e95-8247-d9362edf7cb0', 'BT', 'BT Select Administrator SuperWrap', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by BT.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 188);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('0fc1de30-1f6e-43b1-a365-363ccbe89604', 'ElectricSuper', 'ElectricSuper', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by ElectricSuper.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 113);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('44a20376-fe71-438e-8f07-c660b35842f5', 'TelstraSuper', 'TelstraSuper Corporate Plus', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by TelstraSuper.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 93);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('673c5db7-df87-480e-896b-bd57641edc29', 'Australian Taxation Office', 'ATO-Held Super', 'superannuation', NULL, NULL, NULL, 'Superannuation amounts held by the Australian Taxation Office on behalf of a member.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 477);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('6a4431c1-26e8-479a-9b1b-f758d957c6a1', 'QSuper', 'QSuper Income', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by QSuper.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 380);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('cc0e16a0-a24c-47ea-811a-3583c9f694ee', 'GuildSuper', 'GuildSuper', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by GuildSuper.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 115);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('d8de00f4-90bd-443e-a1b4-c2783706dcd3', 'Auxilium', 'Auxilium Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Auxilium.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 489);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('303dd490-de50-46d7-8fbf-43d6710bd27a', 'Symetry', 'Symetry Active Investment', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Symetry.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 425);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('38c87442-1418-440a-836e-1219585f100e', 'Asgard', 'Asgard eWrap Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Asgard.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 162);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('99185559-65f5-4395-bfaf-87f084e52876', 'PAS', 'PAS - Gold', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by PAS.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 579);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('af3f214e-1175-4228-a097-5c2419adfdcc', 'Child Care Super', 'Child Care Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Child Care Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 117);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('fcc6830b-7187-41a4-b3af-0c6be366930d', 'OnePath / Insignia Financial', 'OneAnswer Frontier Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by OnePath / Insignia Financial.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 344);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('318d4f35-0bfe-472e-af5a-802416d3c976', 'Test / QA', 'ZZ Test Platform Pass3', 'platform', NULL, NULL, NULL, 'QA/test platform record; not a live customer product.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 601);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('781133b5-afdd-4562-8a89-8c68aea70c94', 'Praemium', 'Praemium SMA Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Praemium.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 372);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('a71a9e7f-9438-435e-bd04-a74eb926ccaa', 'FES Super', 'FES Super Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by FES Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 226);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('3bcd6c4e-1096-45b2-8860-09ad364a7c90', 'Praemium', 'Praemium Partner SMA', 'platform', NULL, NULL, NULL, 'Managed-account/SMA investment platform offered by Praemium.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 376);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('0fca44be-9d7b-4e37-be0a-560d3346ebf4', 'Voyage', 'Voyage Investment Service', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Voyage.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 413);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('7cad1e53-42d7-4f90-b1ad-e27e29a092ae', 'PAS', 'PAS - Platinum', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by PAS.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 580);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('188a8881-e63f-4e1d-bb5a-60040f0b415a', 'Asgard', 'Asgard eWrap Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Asgard.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 161);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('46b7e5a1-bc84-4520-9bc6-fe83823e27ec', 'OnePath / Insignia Financial', 'OnePath OneAnswer Personal Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by OnePath / Insignia Financial.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 151);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('5e17691b-03ac-4ceb-bea5-f5eacd6f0c70', 'Macquarie', 'Macquarie Super Consolidator II', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Macquarie.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 282);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('4bd50706-7741-42c5-a769-5b8722e35a47', 'CMC Markets', 'CMC Markets', 'platform', NULL, NULL, NULL, 'Investment/trading platform offered by CMC Markets.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 591);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('a2704075-5535-4a22-8db7-72982a02508e', 'GESB', 'GESB Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by GESB.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 50);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('98e23dd3-1d56-485b-baee-f313e3eac7fd', 'REI Super', 'REI Super Elite Allocated Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by REI Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 80);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('fdd620f6-a432-4433-ada5-4f1a392ce3eb', 'REI Super', 'REI Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by REI Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 79);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('a75893ca-9b1b-4ec6-a8e5-8ecbd80201b3', 'vMAPs', 'vMAPs Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by vMAPs.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 402);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('2f40d75b-dd44-487a-9fd5-8662d4bb3518', 'ipac / AMP', 'iAccess Allocated Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by ipac / AMP.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 429);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('59fa448d-87a6-4af8-8dae-c114a4ccd1ef', 'Acclaim Wealth', 'Acclaim Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Acclaim Wealth.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 476);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('5d18c724-4a35-4b9b-9f64-bf86eadd792e', 'HUB24', 'HUB24 Invest', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by HUB24.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 247);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('ba22a545-e2b5-4e1c-9474-ffdd83b84491', 'Asgard', 'Asgard Infinity eWRAP Investment', 'platform', NULL, NULL, NULL, 'Wrap investment administration platform offered by Asgard.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 163);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('094672d6-fc81-49fb-88de-13db5c588599', 'Catholic Super', 'Catholic Super Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Catholic Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 206);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('ae1432f1-b00a-4ba0-b7e5-d1c83f0620dd', 'Expand / Insignia Financial', 'Expand Essential Investment', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Expand / Insignia Financial.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 271);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('a6b385ea-50f2-470b-9cee-b11078f35d07', 'Asgard', 'Asgard Open eWRAP Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Asgard.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 167);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('223c1d3e-e7ef-4521-bec2-7cf779d5665f', 'ANZ', 'ANZ Staff Super - Account Based Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by ANZ.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 155);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('47d23d0c-7942-4cd4-8e6d-4dc1882b4e37', 'State Super', 'State Authorities Superannuation Scheme', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by State Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 479);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('208f7463-3c09-48f5-aeaf-9b1112924828', 'smartMonday', 'smartMonday PRIME - Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by smartMonday.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 389);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('9c1b0495-1afe-47eb-ab20-d9813ba0d69f', 'ipac / AMP', 'iAccess Personal Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by ipac / AMP.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 428);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('fb13b2c3-9411-4761-9718-9222e0adf3c1', 'Perpetual', 'Perpetual Select Super Plan', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Perpetual.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 353);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('24558b6a-bf0e-4422-af27-e9a83a479760', 'OneVue / Praemium', 'OneVue Managed Account', 'platform', NULL, NULL, NULL, 'Managed-account/SMA investment platform offered by OneVue / Praemium.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 474);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('bd63091e-ea0a-4d40-8f22-6331abc37b80', 'Virgin Money', 'Virgin Money Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Virgin Money.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 101);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('bf2678be-e8e1-4ea7-bed1-256061706ea0', 'Netwealth', 'Netwealth Pension Accelerator Core', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Netwealth.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 442);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('68696403-c55c-4df3-92fd-4346fa57cf2b', 'Commonwealth Superannuation Corporation', 'Military Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Commonwealth Superannuation Corporation.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 66);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('d5645f23-ffdd-417e-87c5-6a2bfc7d71d0', 'KeyInvest', 'KeyInvest Funeral Bond', 'investment', NULL, NULL, NULL, 'Investment bond designed to help fund future funeral expenses, offered by KeyInvest.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 277);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('afb7aced-28e7-4afa-994e-ec6ad80f92db', 'Russell Investments', 'Russell Investments Super Series - Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Russell Investments.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 383);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('68f665c5-9acb-4a82-9ab6-e85adf82815f', 'Symetry', 'Symetry Foundation Investment', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Symetry.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 422);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('107ed57f-41ac-4971-8b55-6797446a82a7', 'Symetry', 'Symetry LifeTime Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Symetry.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 417);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('eb7de7e5-e81a-4827-a4ba-c4ab21548838', 'Fiducian', 'Fiducian Pension Service', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Fiducian.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 578);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('dfbcd821-a82b-4542-92d6-0184094131d4', 'BT', 'BT SuperWrap - Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by BT.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 198);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('64d49496-7d3c-40ab-aac0-227ced08419d', 'Australian Food Super', 'Australian Food Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Australian Food Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 137);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('a8cf7575-f595-412e-ba77-26569cab9eef', 'FES Super', 'FES Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by FES Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 43);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('c6063ea9-faa0-475c-af60-f23ec2b78198', 'Symetry', 'Symetry Foundation Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Symetry.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 421);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('eac292a2-5ba7-4e90-b8d2-e21a1abb7a96', 'BT', 'Asset Administrator Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by BT.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 182);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('21add27b-dc99-40d3-9dea-4483040fbccc', 'Salaam', 'Salaam Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Salaam.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 558);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('2a32e8b2-c642-499e-b650-240467aabc9a', 'HESTA', 'HESTA Income Stream', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by HESTA.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 244);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('6618038f-211e-4379-8658-3d5836838e83', 'BT', 'BT Wrap Open', 'platform', NULL, NULL, NULL, 'Wrap investment administration platform offered by BT.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 202);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('a5d9dee0-3072-4468-ba5a-c368d322ce8e', 'BT', 'BT Panorama Investments', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by BT.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 186);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('b3ecaf3d-3db9-49a9-b196-458d4421a8fe', 'Perpetual', 'Perpetual WealthFocus Super Plan', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Perpetual.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 349);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('12e2ec17-aeb8-4bb2-901d-e2b0c5e354c1', 'OnePath / Insignia Financial', 'OneAnswer Frontier Investment Portfolio', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by OnePath / Insignia Financial.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 345);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('a0e8b115-1453-4490-b4f6-7593fc4b9c11', 'ESSSuper', 'ESSSuper', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by ESSSuper.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 37);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('019dcc5e-08c0-456b-b85b-56422fc1e559', 'Acclaim Wealth', 'AMG Personal Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Acclaim Wealth.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 135);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('27b1ffb2-0e33-496d-92ea-f71c3db9093d', 'First Super', 'First Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by First Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 46);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('2f79838a-3467-47c4-80a5-3cf492c0b537', 'Australian Expatriate Super Fund', 'Australian Expatriate Super Fund - Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Australian Expatriate Super Fund.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 485);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('1c0b43d5-d19f-41ad-821f-8ca566988972', 'NESS Super', 'NESS Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by NESS Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 69);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('ffb82fef-a949-46ab-bfe4-b4ce5b5475b2', 'Australian Unity', '10Invest', 'investment', NULL, NULL, NULL, 'Tax-paid investment bond offered by Australian Unity for long-term investing.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 453);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('243f379a-0e45-4708-95e9-6aa021d0e601', 'Symetry', 'Symetry LifeTime Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Symetry.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 418);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('3676193c-b18a-4940-a8dc-e76c0b882e2b', 'MLC / Insignia Financial', 'MLC MasterKey Personal Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by MLC / Insignia Financial.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 308);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('351ed354-93c4-4fb6-a922-2568af4b2079', 'Generation Life', 'Generation Life ChildBuilder', 'investment', NULL, NULL, NULL, 'Investment bond/product designed for long-term family or education savings, offered by Generation Life.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 234);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('2b023cd8-7a5b-4a09-b479-991ce0c92c5c', 'Ensurity', 'Ensurity Retirement', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Ensurity.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 132);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('6dbb7d4d-8331-407c-be62-2b1b219c875d', 'BT', 'BT SuperWrap Open - Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by BT.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 201);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('6dcdb903-5735-44cb-9a32-6528f5e367cf', 'Insignia Financial', 'Insignia SuperWrap Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Insignia Financial.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 250);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('c137c26d-7c93-4c08-9793-c04920d10926', 'ANZ', 'ANZ Smart Choice Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by ANZ.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 154);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('a4548bbd-6826-44e9-ab75-b4a45f80c551', 'WealthTrac', 'WealthTrac Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by WealthTrac.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 405);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('97d5213c-972d-4d80-a34c-69f7236aa507', 'Australian Retirement Trust', 'Australian Retirement Trust Income Account', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Australian Retirement Trust.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 88);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('decdea15-40d0-4506-930c-ea9d63e3e91c', 'ipac / AMP', 'iAccess Investment', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by ipac / AMP.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 430);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('d5e0f4b3-2dfa-43e0-9035-e83764c16228', 'Agentia', 'Agentia SuperSMA', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Agentia.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 129);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('cbadee4e-abb5-40a2-bbe7-6ef90c2d9a7c', 'UniSuper', 'UniSuper', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by UniSuper.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 97);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('f57b313e-def7-4fe5-b7cb-53f5ae079f98', 'Portfoliofocus', 'Portfoliofocus - Premium Retirement Service Series 2 - Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Portfoliofocus.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 493);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('dde5c896-3fca-45a6-96e9-6331da0ae3e3', 'MLC / Insignia Financial', 'MLC Masterkey Investment Fundamentals', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by MLC / Insignia Financial.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 305);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('661c9e60-415c-4077-bd55-f90bd77e4301', 'vMAPs', 'vMAPs', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by vMAPs.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 404);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('4879936e-60e6-41fe-83ae-62fdae4c2b64', 'AMP', 'AMP Personalised Portfolio', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by AMP.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 144);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('0a983acb-bae0-4743-82a3-470219352fa9', 'BT', 'BT Panorama Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by BT.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 1);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('91c09b2e-af92-4ba5-8922-811767e4551b', 'Super SA', 'SuperSA Income Stream', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Super SA.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 496);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('496fc943-f786-46e1-a4f1-cd104010cc2e', 'AustralianSuper', 'AustralianSuper', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by AustralianSuper.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 17);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('218514bc-8711-40a2-8614-3528ca66d2f5', 'GuildSuper', 'GuildPension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by GuildSuper.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 116);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('0dcf5b4a-68bf-4a61-83e7-a97f2ada5c48', 'Macquarie', 'Macquarie Pension Consolidator', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Macquarie.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 289);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('3ada0ded-70c4-4fad-8d54-9a718e3ab19a', 'KeyInvest', 'KeyInvest Life Events Bond', 'investment', NULL, NULL, NULL, 'Investment bond product offered by KeyInvest.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 276);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('eb131253-cc11-44fd-a101-ec5ce6598c39', 'Prime Super', 'Prime Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Prime Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 73);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('ca56a9d0-45fa-486a-b5c6-12b1ce706b01', 'Ensurity', 'Ensurity Superannuation', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Ensurity.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 131);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('15ba5a03-fb26-4b0d-bf5f-3a3e91fd3fce', 'Sentinel', 'Sentinel Select', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Sentinel.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 514);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('8fa8984d-c367-4c32-8a16-f6d150a4e99e', 'First Super', 'First Super Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by First Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 47);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('f2fa339e-8510-47cf-8d3f-898eb907a315', 'legalsuper', 'legalsuper', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by legalsuper.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 55);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('7131cbaa-0f2c-4b27-818f-7b7dc8ebadb0', 'Resolution Life', 'Resolution Life Guaranteed Annuities', 'pension', NULL, NULL, NULL, 'Annuity/retirement-income product offered by Resolution Life.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 597);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('7630d233-2046-4a5b-b100-e007595a57b1', 'Executive Choice', 'Executive Choice Investments Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Executive Choice.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 555);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('7c7b32a1-54bc-4b90-88e8-59c5791ee894', 'Prime Super', 'Prime Super Income Stream', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Prime Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 74);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('d2b39253-a75f-423a-afa1-4cfcdb5a7697', 'Bendigo Bank', 'Bendigo SmartStart Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Bendigo Bank.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 175);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('8aa25f11-a3fc-42c1-bfa6-e3ceb14b2339', 'Vanguard', 'Vanguard Personal Investor', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Vanguard.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 464);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('96e769d2-d367-459c-91a4-918445135519', 'AMP', 'North Investment', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by AMP.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 342);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('5922f9d4-6f3c-4411-9a52-24ae1debd6e8', 'Generation Life', 'Generation Life LifeBuilder', 'investment', NULL, NULL, NULL, 'General investment product offered by Generation Life.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 233);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('51f5f635-60a4-4a73-996b-eca57be419c9', 'Acclaim Wealth', 'Acclaim Invest', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Acclaim Wealth.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 498);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('53c922b2-ecf9-4335-a72e-7f014ec69969', 'BUSSQ', 'BUSSQ', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by BUSSQ.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 107);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('15d28193-4925-44b4-a4fe-a44660d72568', 'Expand / Insignia Financial', 'Expand Extra Investment', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Expand / Insignia Financial.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 274);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('e481bb3b-81d2-4aee-ba4c-13d94d9cc531', 'Fiducian', 'Fiducian Superannuation Service', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Fiducian.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 472);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('7e762798-8a7f-4289-8e74-7d5099f9e824', 'Perpetual', 'Perpetual Select Pension Plan', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Perpetual.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 354);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('7b7ed30c-c800-47c8-94a2-51b3fb871b2a', 'AMP', 'AMP Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by AMP.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 146);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('b204e1d2-3f80-4cfa-964f-ae659a9406a0', 'Grow Wrap', 'Grow Wrap Investment Service', 'platform', NULL, NULL, NULL, 'Wrap investment administration platform offered by Grow Wrap.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 242);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('4d952166-93a0-4712-b512-02288301dd5d', 'Symetry', 'Symetry Foundation Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Symetry.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 420);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('84bfe29f-0af3-4199-8092-67fad29d90f2', 'Colonial First State', 'CFS Edge Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Colonial First State.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 515);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('a720a618-3b8e-478e-b839-f3aa94ff9f35', 'Xplore Wealth', 'Xplore Wrap', 'platform', NULL, NULL, NULL, 'Wrap investment administration platform offered by Xplore Wealth.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 457);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('1b626361-2f55-4875-899d-684108b9abbe', 'Expand / Insignia Financial', 'Expand Extra Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Expand / Insignia Financial.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 272);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('afea63dc-e02d-4970-bd4b-18aea6d9c5a9', 'Macquarie', 'Macquarie Super Consolidator', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Macquarie.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 290);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('a0785b6a-b01b-495c-a11c-3e799400c070', 'Expand / Insignia Financial', 'Expand Essential Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Expand / Insignia Financial.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 269);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('2ef73f15-a0e1-4205-8101-9c9edd1fb0bd', 'Test / QA', 'ZZ QA TEST PlatformName 25Aug', 'platform', NULL, NULL, NULL, 'QA/test platform record; not a live customer product.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 599);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('2e35e846-c3cd-4725-bb13-145882681039', 'Self-managed / client managed', 'Self Managed Super Fund', 'superannuation', NULL, NULL, NULL, 'Generic self-managed super fund record for accumulation-phase superannuation.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 456);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('14a2b42e-7953-42ba-9460-616527d2f5a2', 'BT', 'BT Select Administrator Wrap', 'platform', NULL, NULL, NULL, 'Wrap investment administration platform offered by BT.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 444);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('f9f653a7-93cc-4a6c-9ba2-7ec393e61a5b', 'Colonial First State', 'CFS FirstChoice Wholesale Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Colonial First State.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 210);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('0c22af56-ab43-4813-9276-885dc71678e6', 'AMP', 'MyNorth Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by AMP.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 2);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('75fc7c30-0a92-41b6-9a9d-2b696ac97004', 'Integra Super', 'Integra Super Personal', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Integra Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 252);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('1b957308-c15e-4303-ba63-f32907384dbb', 'Acclaim Wealth', 'AMG Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Acclaim Wealth.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 136);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('71935b01-4559-4fe7-8f39-20efef89c06e', 'Centric', 'Centric Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Centric.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 576);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('64cc4b43-716f-4731-bb5a-dbac6a310891', 'QSuper', 'QSuper', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by QSuper.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 78);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('819d3367-4506-469d-9be9-dddda8009e42', 'Colonial First State', 'CFS Managed Investment Funds', 'managed_fund', NULL, NULL, NULL, 'Managed investment fund product or fund range offered by Colonial First State.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 543);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('7b7a417f-b2f0-431d-82ce-1068f931c341', 'Australian Unity', 'FuneralPlan Bond', 'investment', NULL, NULL, NULL, 'Investment bond designed to help fund future funeral expenses, offered by Australian Unity.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 280);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('4eb9f539-c918-495d-aaf7-851fb0e6353c', 'Colonial First State', 'CFS FirstChoice Investments', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Colonial First State.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 213);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('2566283b-4c39-4ffd-b480-bb29dbd62f81', 'Portfoliofocus', 'Portfoliofocus - Premium Retirement Service Series 2', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Portfoliofocus.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 492);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('ffddb79a-2ad4-492b-9e8c-faa7234ab77a', 'Rhythm', 'Rhythm Investment', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Rhythm.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 509);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('63d9d93d-2acb-43bd-9daa-a8c16aa7f089', 'Asgard', 'Asgard eWrap Investment', 'platform', NULL, NULL, NULL, 'Wrap investment administration platform offered by Asgard.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 160);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('31b6615a-2605-440c-81c1-ae09146cf52a', 'Mercer', 'Mercer Business Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Mercer.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 537);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('350f6398-3aed-4137-a2f5-af53c040c643', 'Macquarie', 'Macquarie Investment Manager II', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Macquarie.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 284);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('3108c3eb-664e-4da1-b461-09a93cfd2109', 'Colonial First State', 'CFS Edge Investments', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Colonial First State.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 517);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('5db0c381-04f7-4cde-9881-696382277b70', 'Vision Super', 'Vision Super Saver', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Vision Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 102);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('310ae06a-6481-476a-ba76-e88c8f693d72', 'AssetLink', 'AssetLink SuperWrap Pension Plan', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by AssetLink.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 170);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('8985ae30-5e5f-44c1-9e27-13203a98f6ad', 'IconiQ', 'IconiQ Super Wrap', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by IconiQ.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 565);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('a55cc2f1-b707-455f-94b8-9757c03d8e80', 'Brighter Super', 'Brighter Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Brighter Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 60);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('b31d9e29-d566-49b7-92fc-d23b7043c9da', 'NESS Super', 'NESS Account Based Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by NESS Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 70);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('494821a9-4d0d-4893-8ba0-f27036c3839e', 'BT', 'BT Select Administrator SuperWrap - Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by BT.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 189);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('c82651c1-e127-47a9-a140-f93282cef661', 'Superhero', 'Superhero Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Superhero.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 462);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('b5b6e0bd-79a6-450c-9a1a-5586ef3dbd31', 'Integrated Portfolio Solutions', 'Integrated Portfolio Solutions', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Integrated Portfolio Solutions.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 564);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('09e914b8-827b-47a3-b0c3-9d1c197a2db0', 'Resolution Life', 'Resolution Life Growth Bond', 'investment', NULL, NULL, NULL, 'Investment bond product offered by Resolution Life.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 466);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('1abd793a-fba2-48c3-b6f6-77e22ac6c740', 'Shadforth', 'Shadforth Portfolio Service - Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Shadforth.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 526);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('b2bff618-8065-41c2-ae8c-18a5ac52ec51', 'Cbus Super', 'CBUS Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Cbus Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 26);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('fd913cdc-46a1-4f73-8b9c-74bec5f0d69e', 'Asgard', 'Asgard Elements - Investment', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Asgard.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 156);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('b791ea54-3a15-4986-b6c9-549f6a6eeb9b', 'Commonwealth Superannuation Corporation', 'Commonwealth Superannuation Scheme', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Commonwealth Superannuation Corporation.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 569);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('a8c0e4c4-dc57-48f2-990b-eae44a3ef406', 'Colonial First State', 'CFS FirstChoice Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Colonial First State.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 208);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('9afc1306-a092-4d95-a37d-694e95ab8ba8', 'PremiumChoice', 'PremiumChoice Retirement Service Series 2 - Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by PremiumChoice.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 378);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('34f1ab97-f7d1-48ef-9cf6-d0986fe37da1', 'Perpetual', 'Perpetual WealthFocus Allocated Pension Plan', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Perpetual.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 350);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('68793011-67c9-4881-94bb-5eb322a666e5', 'Future Super', 'Future Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Future Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 451);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('4442837a-a045-45e0-95a2-0bc49d296192', 'Macquarie', 'Macquarie Investment Consolidator', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Macquarie.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 291);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('9d7ab8fb-9db2-4b14-a2d6-6c299957d190', 'Portfolio Administrator', 'Portfolio Administrator InvestmentWrap', 'platform', NULL, NULL, NULL, 'Wrap investment administration platform offered by Portfolio Administrator.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 361);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('cf70eefe-852a-4c0e-82a6-b5cbebeb0758', 'Hostplus', 'HostPlus Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Hostplus.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 52);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('bc3f04fd-6d93-4364-8b0b-d040b6a9225f', 'Expand / Insignia Financial', 'Expand Essential Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Expand / Insignia Financial.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 270);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('37d19a9b-a8bf-42bb-9519-bda99e6ba47a', 'AMP', 'AMP Flexible Lifetime - Investments', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by AMP.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 443);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('30b62084-276e-4382-b8d1-5ec146b08f7e', 'Super SA', 'SuperSA Flexible Rollover Product', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Super SA.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 497);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('974e3c44-c1a9-4e8d-87d3-44b2a2babc21', 'AMP', 'North Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by AMP.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 340);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('6dba8dbc-5ecd-4524-99e2-14649e9c58e6', 'Insignia Financial', 'Insignia SuperWrap', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Insignia Financial.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 249);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('06bf47f2-6f86-4196-a9ff-038cb66ebd95', 'Perpetual', 'Perpetual Private Super Wrap', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Perpetual.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 356);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('1a5cfbd2-c17a-45be-8fac-403ad9e409bc', 'GESB', 'Gold State Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by GESB.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 239);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('b7cc06a0-b8ef-42c4-a210-78acd3c5dccb', 'Spirit Super', 'Spirit Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Spirit Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 448);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('cf6d46b6-4c4c-4388-ac80-854c3ba67fec', 'Macquarie', 'Macquarie Pension Manager', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Macquarie.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 294);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('f61e70d1-7dca-48ff-9cdd-4848c2090030', 'Netwealth', 'Netwealth Wealth Accelerator Core', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Netwealth.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 440);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('1f9eed7b-421a-42b4-abf1-3821ccd7efe8', 'Meat Industry Employees Superannuation Fund', 'Meat Industry Employees Superannuation Fund', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Meat Industry Employees Superannuation Fund.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 120);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('532fb43c-44f8-4576-970a-ec353512f2b0', 'Colonial First State', 'CFS FirstChoice Wholesale Investments', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Colonial First State.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 212);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('d1175b5f-0802-47e0-b8b6-620ccbafa380', 'Freedom of Choice', 'Freedom of Choice Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Freedom of Choice.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 518);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('965c4cfe-6ab4-4635-ad60-68ab9d78966e', 'IconiQ', 'IconiQ Investment IDPS', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by IconiQ.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 567);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('430dfdab-0666-42e2-b7fa-8fedae0c8f1d', 'CAREportfolio', 'CAREportfolio Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by CAREportfolio.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 204);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('4545148f-f50d-4f0c-bb90-ff9dbb8d1b9d', 'LifeFocus', 'Lifefocus eWrap Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by LifeFocus.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 550);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('f24f0292-1821-4f7b-80d4-975281a177c2', 'Colonial First State', 'CFS FirstChoice Personal Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Colonial First State.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 207);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('a8ad33b0-d2f4-4d08-9c5f-31370c3cf56d', 'Vanguard', 'Vanguard Super TransitionSmart', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Vanguard.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 545);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('86f6393b-aae2-497d-a1dc-93971d81bf6b', 'Mason Stevens', 'Mason Stevens Global Investment Service', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Mason Stevens.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 299);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('9fb2bb7f-45d1-4d92-961c-eefec7ceb6db', 'Agentia', 'Agentia SuperSMA - Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Agentia.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 434);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('da3ccbf1-5539-4f2a-b51a-85799bed7c1e', 'Centric', 'Centric Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Centric.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 539);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('6d622080-2ecd-42c9-b29c-da260547a575', 'Loyalty Wealth', 'Loyalty Wealth - Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Loyalty Wealth.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 548);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('fafea7e7-921b-4266-9427-c700ecbb5b5d', 'Fiducian', 'Fiducian Investment Service', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Fiducian.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 473);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('d2ddb6e9-61fd-4292-b01d-a103ccdf6d7d', 'Generic / Other', 'Direct Ownership', 'investment', NULL, NULL, NULL, 'General investment product offered by Generic / Other.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 339);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('bb586d9b-f822-4309-8bf0-8735f20feb26', 'Russell Investments', 'Russell Investments Wealth Series', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Russell Investments.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 384);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('ad852a83-cab6-43d3-a3bf-81b381f114fb', 'Colonial First State', 'CFS Edge Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Colonial First State.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 516);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('314d0fd2-0c95-4838-b2c7-a86669ddf93a', 'Macquarie', 'Macquarie Super Accumulator', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Macquarie.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 288);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('649c6e3d-0aab-43b7-b25a-c8aeb8cafb03', 'Platformplus', 'PlatformplusWRAP', 'platform', NULL, NULL, NULL, 'Wrap investment administration platform offered by Platformplus.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 482);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('944fe6e4-5990-4e17-9031-dcf5c468106a', 'Commonwealth Superannuation Corporation', 'Public Sector Superannuation Scheme', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Commonwealth Superannuation Corporation.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 570);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('39d25766-8463-425a-a63c-511cdb429d29', 'Australian Retirement Trust', 'Australian Retirement Trust', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Australian Retirement Trust.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 87);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('eec2ea83-1037-47b1-9aa0-f1a73bbdd261', 'BT', 'BT Super Invest - Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by BT.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 435);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('0b583567-8ec6-43b0-88d3-5fa0f4e9144a', 'Praemium', 'Praemium Partner SuperSMA', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Praemium.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 374);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('e0ef1c2d-c416-4b80-8f5a-e22827c8743d', 'GESB', 'West State Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by GESB.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 49);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('d452c7bf-bb0a-438d-9f4a-c4ac1aa69ea5', 'PremiumChoice', 'PremiumChoice Retirement Service Series 2 - Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by PremiumChoice.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 379);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('d9ca02d9-8843-4f79-8376-a16be72b2c52', 'BT', 'BT Invest', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by BT.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 197);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('a9af41fb-5ef5-4f11-abea-f7079e0fecc0', 'State Super', 'State Superannuation Scheme', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by State Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 478);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('e441baf4-6e64-493b-a0a3-e3753a1779ee', 'Spaceship', 'Spaceship Voyager', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Spaceship.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 410);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('41642acd-1170-499b-bd78-7f891467704f', 'Stake', 'Stake Invest', 'platform', NULL, NULL, NULL, 'Investment/trading platform offered by Stake.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 572);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('836339ce-d351-4ec5-8c85-b36c300a9e99', 'Perpetual', 'Perpetual Private Investment Wrap', 'platform', NULL, NULL, NULL, 'Wrap investment administration platform offered by Perpetual.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 355);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('1176bdd4-e28c-43b8-94c0-64ed55a692bd', 'Auxilium', 'Auxilium Investment Service', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Auxilium.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 491);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('7cb14fb8-903f-45ae-a4f3-11ac731d300e', 'Symetry', 'Symetry Active Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Symetry.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 424);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('7dd833af-c20e-4d30-a2f3-023095697b96', 'Centuria', 'Centuria LifeGoals', 'investment', NULL, NULL, NULL, 'General investment product offered by Centuria.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 465);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('c0af465a-d605-468e-979f-9a67e47504d8', 'Active Super', 'Active Super Retirement Scheme', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Active Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 58);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('46e87b79-f575-4bd8-b5d6-d05f30588bcf', 'NEO', 'NEO SuperSMA', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by NEO.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 332);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('c2f4cd3f-96ca-4cf1-81ed-aad2ccbdd533', 'Team Super', 'Team Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Team Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 122);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('014465fe-c670-44f8-9000-bb784bf581a9', 'IOOF / Insignia Financial', 'IOOF Personal Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by IOOF / Insignia Financial.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 258);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('ec837cab-ca91-4c2f-b8c2-0f27b23dd4eb', 'AMP', 'MyNorth Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by AMP.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 331);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('528b6436-cda0-412f-b146-55e8ee5e2d94', 'Brighter Super', 'Brighter Super Pension Account', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Brighter Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 61);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('d4ba8205-3bb5-4309-89ad-75dd7b71abf1', 'Media Super', 'Media Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Media Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 64);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('0b3af772-7aa6-437d-912a-19a7e0e4f654', 'Catholic Super', 'Catholic Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Catholic Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 23);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('c75efea0-4763-4da4-9e97-7ef2beea3a78', 'PremiumChoice', 'PremiumChoice Investment Service Series 2', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by PremiumChoice.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 377);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('986881ad-5a72-4e27-8b02-545fe9278f29', 'IOOF / Insignia Financial', 'IOOF Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by IOOF / Insignia Financial.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 259);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('3bd1f960-ac09-4ea1-9aab-98642328a2b1', 'Australian Food Super', 'Australian Food Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Australian Food Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 13);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('3da07703-6174-4a44-8a7a-c1b2a36ee6d1', 'AMP', 'MyNorth Lifetime Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by AMP.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 504);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('dfb13c6d-daaf-4bda-b31e-a51696a1b908', 'Russell Investments', 'Russell iQ Retirement', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Russell Investments.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 385);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('812a872a-93d1-4961-b43c-4b2cc7b1c2d5', 'Asgard', 'Asgard Infinity eWRAP Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Asgard.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 164);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('8bacfd69-7bc5-40ec-b529-eeb4ec132e29', 'NGS Super', 'NGS Super - Allocated Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by NGS Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 72);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('79e067b0-5fb9-4a9a-aef4-007dd3ace8c6', 'Vanguard', 'Vanguard Super SaveSmart', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Vanguard.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 502);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('31d329b9-d924-4c06-9164-b2895c87dd9a', 'Meat Industry Employees Superannuation Fund', 'Meat Industry Employees Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Meat Industry Employees Superannuation Fund.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 121);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('57b42fb4-6310-4205-949a-c7e8be090cff', 'Apex Macro Financial Group', 'AMFG - Superannuation', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Apex Macro Financial Group.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 561);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('4ac7266a-212a-43a1-ac53-f48c81bad0da', 'Nationwide Super', 'Nationwide Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Nationwide Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 431);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('671db638-6a67-4ab7-b40a-b9745f98e591', 'Macquarie', 'Macquarie Investment Accumulator', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Macquarie.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 287);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('214f485d-a990-4ee8-b345-d060d86d60c3', 'Shadforth', 'Shadforth Portfolio Service - Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Shadforth.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 527);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('ac7beb2d-9120-4ad2-bdd8-e6057ee6cfff', 'BT', 'BT Select Portfolio InvestmentWrap', 'platform', NULL, NULL, NULL, 'Wrap investment administration platform offered by BT.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 190);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('db92f034-3751-47cf-99be-d091128e56ca', 'Macquarie', 'Macquarie Super Manager', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Macquarie.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 293);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('0bed2891-02f5-40bc-bb14-71a8e6c37fc8', 'BT', 'BT Panorama Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by BT.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 185);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('6b254547-35af-4997-bb45-63095872eba7', 'Australian Expatriate Super Fund', 'Australian Expatriate Super Fund', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Australian Expatriate Super Fund.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 484);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('df64e23f-8573-431a-b146-20e398e09844', 'Acclaim Wealth', 'Acclaim Core Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Acclaim Wealth.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 427);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('386dde39-1dca-4c7c-85b4-468fe54442fe', 'WealthTrac', 'WealthTrac Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by WealthTrac.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 406);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('3d2296e6-472b-4044-9cd7-ed7f9a8a00b3', 'Xplore Wealth', 'Xplore Managed Account', 'platform', NULL, NULL, NULL, 'Managed-account/SMA investment platform offered by Xplore Wealth.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 529);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('77612397-e333-40cd-8fca-52e235985613', 'CAREportfolio', 'CAREportfolio Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by CAREportfolio.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 203);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('a3136860-204f-4f7a-9f6b-9ce7d606440d', 'Mason Stevens', 'Mason Stevens Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Mason Stevens.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 298);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('87726f7f-a3af-4689-b098-d1eaa9679c4a', 'BT', 'BT Select Portfolio SuperWrap', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by BT.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 191);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('be20bb8a-513f-4e8f-bf7b-b4824d4e6b93', 'Aware Super', 'Aware Super Future Saver', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Aware Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 99);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('a0eddf3e-3d16-4815-ba89-929e1a684bcf', 'Resolution Life', 'Resolution Life Retirement Security Plan', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Resolution Life.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 542);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('affa3e78-0d4b-4177-afaa-dc4b8eb251a6', 'CareSuper', 'CareSuper', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by CareSuper.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 21);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('4e5a9ef0-292d-434f-a3f0-9f13cbdbb447', 'Centric', 'Centric Investment 2', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Centric.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 541);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('dfd84de0-b8c9-4a43-9510-2a5f21b6cb7a', 'TelstraSuper', 'TelstraSuper Personal Plus', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by TelstraSuper.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 94);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('acbbb28f-68e1-4ab8-a7f1-424a67b1b68c', 'Macquarie', 'Macquarie Super Manager II', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Macquarie.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 285);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('09d29d08-a042-42dd-ba59-dd43e3cdf115', 'ClearView', 'ClearView WealthFoundations Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by ClearView.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 215);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('580c2129-d6b2-4eca-929b-8266d4aa0788', 'Executive Choice', 'Executive Choice Investments', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Executive Choice.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 556);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('eac910c6-a0ca-4c84-857d-e7df0cb74602', 'Mason Stevens', 'Mason Stevens Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Mason Stevens.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 297);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('0b2b31b2-6d8b-43d7-8fe2-0a4cb883e53b', 'Commonwealth Superannuation Corporation', 'DFRDB', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Commonwealth Superannuation Corporation.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 571);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('4a4c4f77-a060-4bc0-937e-4cc08dfe2132', 'Shadforth', 'Shadforth Portfolio Service - Investment', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Shadforth.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 528);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('9d3f4bf5-fb2c-4f3a-801a-8864c76ed8d1', 'Vision Super', 'Vision Personal', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Vision Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 103);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('ac075158-b456-4acc-892f-2f1ee0af67e2', 'AMP', 'MyNorth Lifetime Income', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by AMP.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 506);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('13373a9d-57df-4ea2-82f1-a76a04fcf7ad', 'BT', 'BT SuperWrap', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by BT.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 199);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('78fa96c5-2680-43f6-a67d-7e5f0cc6604e', 'Macquarie', 'Macquarie Pension Manager II', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Macquarie.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 286);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('6419141c-b9ed-45fe-8708-f4ca28bd42a9', 'NAB', 'nabtrade', 'platform', NULL, NULL, NULL, 'Investment/trading platform offered by NAB.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 594);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('b53e0830-3ed2-4869-8a24-6885793054ec', 'Oracle Investment Management', 'Oracle Managed Account Series 2', 'platform', NULL, NULL, NULL, 'Managed-account/SMA investment platform offered by Oracle Investment Management.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 536);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('5b54c1b6-6798-457c-9899-43d5edb59ec6', 'Bendigo Bank', 'Bendigo SmartStart Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Bendigo Bank.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 176);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('4ffa0414-d2c3-42be-856e-4ba669b2dae1', 'ANZ', 'ANZ Smart Choice Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by ANZ.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 153);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('8fdebfd2-449b-45e6-82da-29c6ae8d1686', 'Aware Super', 'Aware Super Retirement Income', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Aware Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 100);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('4b72646a-68a2-4863-8004-4bede67b833f', 'Equip Super', 'Equip Super Retirement Income', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Equip Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 36);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('d7f16286-e575-42dd-888e-6d5ef488ecbd', 'Russell Investments', 'Russell iQ Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Russell Investments.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 386);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('98515883-8a97-4a07-8d36-0027251741b4', 'MLC / Insignia Financial', 'MLC Masterkey Pension Fundamentals', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by MLC / Insignia Financial.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 304);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('844d0ed2-b9ec-4f5c-b768-07c8dfa9fb45', 'HUB24', 'HUB24 Private Invest', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by HUB24.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 595);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('54c7e81b-2773-442f-8f23-5c756fd7bf31', 'BT', 'BT Super Invest', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by BT.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 196);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('8443564b-e96e-4152-9d35-90f1e08e6243', 'Auxilium', 'Auxilium Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Auxilium.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 490);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('76b39ebe-e883-4502-862a-bd75a9ea5161', 'Acclaim Wealth', 'Acclaim Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Acclaim Wealth.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 475);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('730be8fd-60dc-42ac-b678-5c46eaac59ac', 'Vision Super', 'Vision Income Stream', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Vision Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 104);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('f31aeb3d-62d0-42a4-8ef2-f47f3c5104f3', 'Cbus Super', 'CBUS Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Cbus Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 27);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('424e6556-584b-46c9-9b36-889ad43d85eb', 'ClearView', 'ClearView WealthFoundations Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by ClearView.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 216);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('de5c113d-8308-4f38-8908-6a34f8913a2d', 'SIX', 'SIX Invest', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by SIX.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 596);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('31c9b6b9-a1bc-4228-9917-1e52cda01668', 'ANZ', 'ANZ Staff Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by ANZ.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 14);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('4c888116-8ffe-4c91-914d-fd2c1ee5b0f9', 'Futurity', 'Futurity Education Bond', 'investment', NULL, NULL, NULL, 'Investment bond/product designed for long-term family or education savings, offered by Futurity.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 460);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('ef6b238b-fbd7-4263-9642-635a2c3c10ee', 'CAREportfolio', 'CAREportfolio Invest', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by CAREportfolio.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 205);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('9099dc41-284b-4a40-8a7f-0edb884397ec', 'BUSSQ', 'BUSSQ Pensions', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by BUSSQ.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 108);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('1da420fb-cf21-4189-b9d8-f5bd733430de', 'Mercer', 'Mercer SmartSuper Plan', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Mercer.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 300);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('3d161e68-1477-4ac9-bccf-8eb1c8f10fed', 'Voyage', 'Voyage Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Voyage.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 412);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('a29c1d6e-a5ea-4672-860b-72ffa8508d1d', 'ESSSuper', 'ESSSuper Income Stream', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by ESSSuper.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 38);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('655bf99d-9f83-4434-ace3-baebc12a5729', 'DASH', 'DASH Wealth Simplifier', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by DASH.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 470);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('70d291cd-c7e8-49cb-9961-2f433d29d481', 'Apex Macro Financial Group', 'AMFG - Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by Apex Macro Financial Group.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 563);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('50165f91-aa77-4ee6-abac-d167117b183d', 'QSuper', 'QSuper Defined Benefit', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by QSuper.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 546);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('01c5793b-32de-4225-9cad-11906101726e', 'HUB24', 'HUB24 Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by HUB24.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 245);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('d9578556-b3dc-4a52-98a3-0e3aaa7c87f4', 'AMP', 'North Pension', 'pension', NULL, NULL, NULL, 'Retirement pension or income-stream product offered by AMP.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 341);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('1cd27bdf-24bd-462d-a85a-e9a94cec28b6', 'AUSIEX', 'AUSIEX', 'platform', NULL, NULL, NULL, 'Investment/trading platform offered by AUSIEX.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 532);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('82f31e60-5455-41fd-839c-0f1a0b0ce4e2', 'smartMonday', 'smartMonday PRIME TESF', 'platform', NULL, NULL, NULL, 'Managed-account/SMA investment platform offered by smartMonday.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 390);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('69d15bd9-dde8-4d4d-b1cb-cac13fd08126', 'Resolution Life', 'RLA Personal Super Plan', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Resolution Life.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 148);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('568c18a8-8267-4c2a-bcc6-b53c7506bc07', 'Australian Unity', 'Lifeplan Investment Bond', 'investment', NULL, NULL, NULL, 'Investment bond product offered by Australian Unity.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 278);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('20ad75cd-66f6-4b6d-a8b7-21b0129b1696', 'Plum Super', 'Plum Super', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Plum Super.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 307);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('2cd362ef-cad8-4fb7-ac9a-3dcd48e35fec', 'Ensurity', 'Ensurity Investment', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by Ensurity.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 134);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('46b5d852-1d98-4f1d-abb3-b51539644589', 'OnePath / Insignia Financial', 'OnePath OneAnswer Investment Portfolio', 'platform', NULL, NULL, NULL, 'Investment administration/platform product offered by OnePath / Insignia Financial.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 150);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('80e5f57c-f49d-47fb-9ae7-a5538ec04037', 'Super SA', 'SuperSA Triple S', 'superannuation', NULL, NULL, NULL, 'Superannuation/retirement savings product offered by Super SA.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 89);
INSERT INTO public.financial_product (id, provider_name, product_name, product_category, product_subcategory, product_code, external_id, description, is_active, source, last_synced_at, created_at, updated_at, rex_id) VALUES ('66291d63-b6de-450c-8948-4d5aaffba3d9', 'Agentia', 'Agentia Investment SMA', 'platform', NULL, NULL, NULL, 'Managed-account/SMA investment platform offered by Agentia.', true, 'rex', NULL, '2026-10-06 07:08:23.009119+00', '2026-10-06 07:08:23.009119+00', 130);


--
-- Data for Name: financial_product_category; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.financial_product_category (code, name) VALUES ('cash_account', 'Cash account');
INSERT INTO public.financial_product_category (code, name) VALUES ('savings_account', 'Savings account');
INSERT INTO public.financial_product_category (code, name) VALUES ('transaction_account', 'Transaction account');
INSERT INTO public.financial_product_category (code, name) VALUES ('term_deposit', 'Term deposit');
INSERT INTO public.financial_product_category (code, name) VALUES ('credit_card', 'Credit card');
INSERT INTO public.financial_product_category (code, name) VALUES ('personal_loan', 'Personal loan');
INSERT INTO public.financial_product_category (code, name) VALUES ('home_loan', 'Home loan');
INSERT INTO public.financial_product_category (code, name) VALUES ('investment_loan', 'Investment loan');
INSERT INTO public.financial_product_category (code, name) VALUES ('vehicle_loan', 'Vehicle loan');
INSERT INTO public.financial_product_category (code, name) VALUES ('investment', 'Investment');
INSERT INTO public.financial_product_category (code, name) VALUES ('managed_fund', 'Managed fund');
INSERT INTO public.financial_product_category (code, name) VALUES ('etf', 'ETF');
INSERT INTO public.financial_product_category (code, name) VALUES ('share', 'Share');
INSERT INTO public.financial_product_category (code, name) VALUES ('platform', 'Platform');
INSERT INTO public.financial_product_category (code, name) VALUES ('superannuation', 'Superannuation');
INSERT INTO public.financial_product_category (code, name) VALUES ('pension', 'Pension');
INSERT INTO public.financial_product_category (code, name) VALUES ('insurance', 'Insurance');


--
-- Data for Name: goal; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: investment_option; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2caea8a2-0a87-482c-81ba-eed7712b3563', 'Australia Post Defined Benefit', 15044, 87, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('fcab5ab8-3c3b-4364-92fa-32f38497e895', 'AMG Index Australian Equities', 9780, 136, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a291b37c-12f5-41be-bd6d-37ad292ff027', 'AMG Index Australian Equities', 9780, 135, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a1dcd910-d93c-412b-9c85-0492e53f7e35', 'Secure', 55, 137, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7255b264-fd17-41fc-98e3-9eac9ef4230f', 'AMG Index Conservative', 9775, 135, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3a8812e9-0e09-44a1-b0cb-d38855df8478', 'AMG MySuper', 9784, 136, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('48aefbfc-0648-4ac1-88d8-44419af20334', 'Australian Shares', 897, 109, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a64df226-f899-4fff-9a54-a8f416d76d77', 'AMG Index Growth', 9777, 136, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d13d1e48-36a9-49c0-8f4e-ecbe48812087', 'Balanced', 733, 88, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5dc0d78b-5527-4f7c-9606-4d40dd37422e', 'AMG Index High Growth', 9778, 136, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c105f5dd-8c00-46f9-b6a8-b0f2326a35b4', 'AMG Index High Growth', 9778, 135, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('655acb58-3905-46ce-be68-d7fa497a11dc', 'Balanced', 893, 110, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7c86feea-a1cf-4a41-8f7a-4b474e7f916e', 'Conservative', 892, 109, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3552dbfe-9250-417a-9ac9-9ab464be1d6e', 'Cautious', 68, 155, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('05c8f937-c6e5-4f08-9b68-8229fcada848', 'Alternatives', 997, 137, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('66bdebbe-8111-43cf-a605-cea578cf78cf', 'Balanced', 733, 87, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1b19f3fa-6ed6-4fc0-836d-a012574015e1', 'International Shares', 896, 109, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('8246b9f0-8b7c-44a0-bcf3-ed522f4e6350', 'High Growth', 895, 109, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('471ae3a0-b23b-41eb-a0a6-e0b6ae455c74', 'Growth', 894, 110, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7bbb45d4-70f1-4261-b3e8-2b8cedf6b11e', 'Balanced', 900, 110, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a6484bfb-a024-4217-b044-0e3395ad2d31', 'AMG Index Conservative', 9775, 136, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4d98c8a6-be2e-4f95-a23b-f0765606209c', 'AMG MySuper', 9784, 135, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('eb47e97d-cf62-495f-bea9-21edbf798afc', 'Aggressive Growth', 60, 155, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4e5dd2b5-368a-4956-9ccd-89c8f5d330e2', 'Defensive', 891, 110, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f76f4034-118c-49b0-9e98-7094d3d30a90', 'Australian Shares', 897, 110, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3a01ffd9-4bf2-4ce0-b9bc-fecf32edbe1d', 'AMG Index Growth', 9777, 135, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b7ac66fa-2901-4cfc-8d78-1d9a5ec5ac94', 'Conservative', 892, 110, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c4bd348b-8e23-4cd8-a304-0eb9a247e37f', 'Balanced Growth', 67, 155, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a0cc3865-b2d1-4416-9f5a-579dfdb71c49', 'AMG Index Balanced', 9776, 136, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ff22b64b-b22f-4abb-b325-17a4f3fce138', 'AMG Index Listed Property', 9782, 136, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7014a6aa-e8a8-4e3a-b6df-d747067e0820', 'Balanced', 54, 137, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e1abac4c-dd07-4ecf-90ef-04fd579637a1', 'Australian Shares - Index', 741, 88, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('412dc65e-874d-4af4-b2a8-135f2bcf9eec', 'AMG Index Cash', 9783, 136, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('addcf242-4e00-48f3-973e-42bbbe71b10e', 'Defensive', 898, 110, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('fe14a40f-e96e-4260-9abe-f8a0d6ba4dbe', 'MySuper', 57, 137, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d6f1abf5-bee0-47ba-af30-de6e284b6eb2', '10Invest - Vanguard Growth Index Fund', 15377, 453, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('04279a0c-355c-43db-accb-92df9ef40679', 'Aggressive', 10150, 487, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f3315b7d-2b1b-4c7e-9d36-f48f0dd6f9f1', 'MySuper Balanced', 10149, 487, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e2a71c14-d1c3-4531-a659-4cc6a7eb860c', '10Invest - Vanguard Ethically Conscious International Shares Index Fund', 15373, 453, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5b37b930-1f63-4ed8-83e3-938981a21f57', '10Invest - Vanguard Balanced Index Fund', 15374, 453, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('65773313-2acf-4a47-b3ec-51ab6163baff', '10Invest - Vanguard International Shares Index Fund', 15378, 453, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d44a35f8-1833-4f74-b2ad-788ba1abf268', '10Invest - Vanguard Conservative Index Fund', 15375, 453, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6f4be557-cc31-4369-920e-aa21ce01851d', 'Cash', 10147, 487, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('809e3dd8-bc89-4b2e-96c6-36b02d867462', '10Invest - Vanguard Australian Shares Index Fund', 15376, 453, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e50628b6-a2cd-480f-950c-ee3bf4d8fd28', 'Income Focused', 10148, 487, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('769c5873-5b79-465c-9548-a93c6d7ca4dc', 'Bonds', 10445, 100, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('911cb12c-76a9-4b39-af81-844ce861e8df', 'Bonds Index', 748, 88, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('12e36dd9-4e18-4239-a461-031625a6969b', 'Conservative', 836, 99, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c6740d3d-f447-4480-be02-c310436ad178', 'Conservative Balanced', 10431, 99, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('57537d96-b894-462a-91de-672338aa524a', 'Property', 10443, 100, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('cde4ea06-58ce-4068-8686-36f0f05e158f', 'Balanced Risk-Adjusted', 13854, 88, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('dfbce596-3cc6-42a0-b5a5-4a89ea4f1f2a', 'Defensive', 1022, 100, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1cb5d1a8-b540-446d-84ee-0458f7cd08ac', 'High Growth Index', 13855, 87, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f4b92e91-6662-424a-acd5-182fe6938225', 'Socially Conscious Balanced', 735, 88, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0ef33cfc-14e3-4603-9679-0c9fa5a2f3e6', 'Conservative Balanced Socially Conscious', 1018, 100, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7adac944-361b-4234-9614-4a353a5e0d51', 'Unlisted Assets', 736, 88, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f2c93865-a357-4dd4-b8c0-c36076523ffe', 'High Growth', 732, 87, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e98ac139-563b-49cc-b4b7-a0bb2918aad1', 'Cash', 6283, 100, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b974dfa3-e996-4609-a621-5c964c152bf7', 'International Shares - Index (unhedged)', 743, 88, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5b0dfb2a-c814-4133-9847-a0da65ed52a1', 'Property', 10436, 99, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('166f35e7-2ff8-4f3a-870a-d3f4d8cc438e', 'Unlisted Assets', 736, 87, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f127989e-111a-4f8d-b2c3-7d4eead0d64d', 'Australian Shares', 841, 99, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('af1359f2-a7e8-4e0e-bb1f-049dcfc0dd9d', 'High Growth Socially Conscious', 10432, 99, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d2c2d96c-7296-448d-a508-5aa6ade79dcf', 'Balanced Risk-Adjusted', 13854, 87, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('75d8abc2-9ccc-42c6-a87a-6e7a886ea3af', 'Bonds Index', 748, 87, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('016ad4b7-8f7c-477a-85e1-59977dcebd09', 'High Growth', 732, 88, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0238ef97-a367-4411-acb4-ce07eac3a14f', 'Australian Shares', 6282, 100, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2499412d-b29f-4c7e-9dd6-0ee761fd9b90', 'Listed Property Index', 746, 88, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('861c678e-7da0-4edb-ac4c-61c8f27328f9', 'International Shares - Index (Hedged)', 742, 88, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('99824433-7f21-4d8b-ba7b-cd605fe17cda', 'International Shares', 10442, 100, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1e80e94b-4549-43eb-8f57-d8688ba6916b', 'International Shares - Index (Hedged)', 742, 87, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6f9377fb-bfd2-4c68-a488-2a49fb5e1732', 'Conservative Balanced Indexed', 10440, 100, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('410c65ae-aeef-4a99-89c9-05337e7caf2b', 'Conservative Balanced', 11282, 100, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('76f18414-b97f-4116-b766-acd85eae3e22', 'Cash', 749, 88, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a0d2d7d8-98f3-4ddf-88b1-0fd9aca2a376', 'Balanced', 1020, 100, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('02e18723-6c93-46ff-aecc-63240e7d410e', 'Balanced - Index', 734, 88, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('97f0b0ac-2950-4ebf-92ad-4b303135b14f', 'Socially Conscious Balanced', 735, 87, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ea5ede2c-a390-4b6d-b913-c4a96ddcfee2', 'Conservative Indexed', 10441, 100, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('8b3070dd-5977-41aa-965a-4d8069eaa015', 'Balanced Indexed', 10434, 99, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9cb51f7d-e1e9-4333-ab86-4ec9c2a480bc', 'International Shares', 10435, 99, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6975aabc-d7b4-4c15-99ed-f449d97ac58d', 'Term Deposit', 6284, 100, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7fa568df-650f-4d12-8823-4431c6b28926', 'Conservative', 738, 88, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e46c8caa-2e9a-4660-b89c-e5dd7dc09d84', 'Conservative', 738, 87, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3fd84c7b-105d-474e-ba39-5e38b63a91f5', 'High Growth Index', 13855, 88, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a5d1f1b9-36ee-4739-881b-a4556d58baca', 'Balanced Socially Conscious', 838, 99, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ea9d7ccb-a4e9-474d-8abc-a81fcc91575f', 'Conservative-Balanced', 737, 87, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('cac7f625-17bf-4dc7-8ee1-2b2f49cb539f', 'Conservative-Balanced', 737, 88, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f7195883-a013-47d4-b00b-b1fb43b7e85e', 'Conservative Socially Conscious', 10439, 100, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('299ae1cd-a359-43d7-81b2-67077ee34905', 'Balanced - Index', 734, 87, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('94f1847b-233b-4e24-9797-afcd58b1f78a', 'High Growth Indexed', 10433, 99, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2dcf4717-2fbc-4202-8522-d4720da818f4', 'Cash', 833, 99, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('721362d0-31ec-4d25-b73a-eeffab1525c7', 'Indexed Diversified', 192, 206, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e1662c4b-a30e-4a63-93df-8668d1540723', 'Cash', 884, 107, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ee4e5e63-696f-40db-afbd-35b2e2001355', 'Balanced Growth (Mysuper &Premium Choice)', 882, 107, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('dc3b5863-e011-49f8-8a88-b367c5e843a6', 'MySuper', 196, 206, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c083b5c6-efbf-48a9-b6b8-fa9a14720a94', 'Balanced', 193, 206, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('740d1ffd-7b2e-4dc6-82e3-8a6b5ef81f52', 'Diversified Fixed Interest', 201, 206, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d111d6f8-d4b2-4736-a172-4f76a52b0546', 'International Shares', 889, 107, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4550fd90-87eb-4721-9bb1-c8b66c92c0b4', 'Capital Stable', 194, 206, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ee235eeb-9f74-4ae9-a9d4-b9b881ce5156', 'Balanced Growth (Mysuper &Premium Choice)', 882, 108, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6711b2b3-35c0-43b3-9471-f3a7ea1c8641', 'Overseas Shares', 199, 206, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6ed1a48b-e0e0-4b02-acfe-da8753f260e7', 'International (Emergingmarkets) Shares', 890, 108, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b10c88ff-4cbe-46c1-88b8-eb3fab0dac14', 'Australian Shares', 198, 206, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3ba3fa22-94db-4266-aa47-e2aaede503bd', 'Defensive', 881, 107, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ea9d6ee1-0583-4fce-86f3-6656e084a062', 'Australian Shares', 886, 108, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('42ca719e-0301-40b0-8da8-7ab95b6d9c95', 'Growth', 190, 206, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3ed38139-59ac-4717-b03c-a1cbf36fdccf', 'Cash', 202, 206, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2971bfff-758d-490a-b0c6-efd0b29fd5a8', 'Future Focus', 195, 206, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('83a18df5-cf23-43e5-8aa2-3de9c7362d86', 'Balanced Growth', 191, 206, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('bb3ef27a-156c-40b2-bcf9-48c58ee5735e', 'Australian (Small Companies)Shares', 887, 107, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f7045f49-305a-4e81-88d9-3488a56d9b7f', 'High Growth', 883, 107, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('33a49db8-033e-46c4-885f-3b280523c10c', 'High Growth', 883, 108, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5a633e17-4c5b-45ef-9f0b-197bc8eaae83', 'Australian Shares', 886, 107, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3563a96e-b8a0-469b-af46-19e6ead90624', 'International (Emergingmarkets) Shares', 890, 107, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0bce6e90-651b-4edd-aa9e-3962463eead4', 'Defensive', 881, 108, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e22e3bb9-5d74-4900-a815-320400cc8796', 'Australian (Small Companies)Shares', 887, 108, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b9dfb999-8f42-4dac-bb9f-79b726599bed', 'Growth Plus', 189, 206, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a9307fd8-58fa-435b-bcee-42a0bc7771f7', 'Cash', 884, 108, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('dae8c82d-2bca-4826-b4e2-9d15a5be99c4', 'International Shares', 889, 108, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3f2ced23-81d6-4432-9c18-5fa17f582821', 'Moderate', 370, 226, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('428f8f3f-5288-4031-92f9-4176de859d0d', 'Balanced Global', 10949, 426, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7fd9d25f-e1b5-48ee-ba70-7623f270166a', 'Growth', 10947, 426, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('80b9b4c9-1f48-4ebf-8c3d-ec97c25d676a', 'Growth', 373, 226, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('152889df-b0cf-4e2e-93d9-0068ad72c761', 'Smoothed', 369, 226, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1cac9bbe-1e8a-4f4c-8f2b-5ea976b8d8a0', 'Balanced Growth', 919, 113, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e2640046-06cc-428d-acc4-b37cfe346782', 'Sustainable Alternatives Growth', 15842, 451, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7936f86e-3a21-4371-8374-365d910ee148', 'Conservative Growth', 920, 114, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0df4e2c2-85cb-4cc3-b220-526dc42d3764', 'International Shares', 374, 226, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4af98c83-b031-4a41-a6dc-2d6486709f34', 'Fixed Interest', 372, 226, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3bde2c2f-c77a-4a68-bb28-df315eb76aa7', 'Balanced Growth', 919, 114, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f2edf5cc-85b4-43a5-bf04-206fe70acc0d', 'Cash', 371, 226, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5be3b350-9dcc-4294-aea2-1feb48894160', 'Cash', 917, 113, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('61731b13-9ab0-45c4-a1d9-4c5c7af8a96e', 'High Growth', 918, 113, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2b428696-019d-451a-a27f-3dc1241c5c20', 'High Growth', 918, 114, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a10c04d9-9ca0-4498-8951-74510491bf24', 'Balanced', 10948, 426, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d573d945-eb44-4066-9b40-fc7b534a27a3', 'Conservative', 10946, 426, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9e983a9b-9fbb-4164-8abc-05e1b00b6b61', 'Conservative Growth', 920, 113, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('88a73dd6-eeb9-4bc7-8440-57857d28ece4', 'Australian Shares', 375, 226, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('647bfa66-5f6c-4b94-9553-364760c03023', 'Balanced', 6301, 451, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('de576f98-9f72-4024-9822-95998b6b7dd2', 'Cash', 917, 114, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('17cbd35f-0a8f-4bd2-a053-aa3a518b3e10', 'Sustainable Alternatives Growth', 15842, 452, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('13b16af3-b4ec-40a0-ad83-117d3717e52d', 'Cash', 11218, 487, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e9668311-663c-44ff-bb13-0d46c8546858', 'Income Focused', 11219, 487, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('65d6d9e9-862b-4a01-b0d2-1c809d19d3cc', 'Challenger Guaranteed Annuity', 10151, 486, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ecbf4acb-8de6-48e6-bc3d-efda620cb132', 'Income Focused', 11219, 520, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('fabaef0b-0782-4e4f-b548-e36a05e95551', 'Balanced', 11220, 520, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('fbbb352c-8c86-4313-b5b9-c3753212ec77', 'Sustainable Balanced Growth', 15840, 451, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2cc96c95-59f8-444d-a007-eed04ee590c1', 'Balanced', 11220, 487, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f9c6333e-9332-494f-9fa0-b7bac8ce81c5', 'Sustainable Growth', 15839, 451, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a5c8fd01-1f64-4661-8bbe-4f1cfb11e9f8', 'Aggressive', 11221, 520, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('aa58673e-888c-41ca-b3ea-271f4d35dff2', 'Defined Benefit', 15040, 569, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f13f0231-adba-4c7c-b119-9ea94c4d2d21', 'Balanced', 6301, 452, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('00854ee2-6c45-403f-ad14-cb3efa88b737', 'Sustainable Balanced Growth', 15840, 452, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2a85b363-17df-407d-adb4-fa3b78b9ac8f', 'Aggressive', 11221, 487, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('cf4b012c-c1f5-4c45-bb48-1edf2f5b7fc2', 'Defined Benefit', 15042, 571, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ae271d3f-594f-4261-94f0-8380d5e5ef50', 'Cash', 11218, 520, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('991b5d6d-ed7c-4b5f-85b9-96f9025f4f8b', 'Building', 921, 117, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e8c59ce4-87ba-4e9c-8218-3313270e0fb4', 'Growth', 927, 116, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('dcc24f2a-41ae-4879-8dfb-b81a256085bf', 'Balanced', 926, 117, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3b37a56e-7970-471f-ac9e-5c52a7aa638d', 'Building', 921, 116, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e91ad503-1d4c-4894-a018-6dd5b628fc3a', 'Consolidating', 923, 116, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c0110e93-2000-4f0e-bc47-8c0630429f7a', 'Australian Shares', 6294, 244, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('34dbf57e-5124-4868-8659-6016b1b4d2d2', 'Secure', 924, 117, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a5e5698f-5645-4cf2-9f63-d8efd22b7416', 'Defined Benefit Scheme', 9656, 239, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('8287bc76-8a7f-43f2-b061-ab8ad4df8b8d', 'Balanced', 926, 115, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e38fa02a-6dfa-45dd-9547-d71873168450', 'Growth', 927, 117, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f86ce1be-047f-41c3-9e66-4c5b4fe1055f', 'Growing', 922, 116, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d1d4e9f3-4394-4cb0-9549-6ef24a6714d3', 'Secure', 924, 115, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d8c76250-6f97-4933-b160-bf22eb2a075c', 'Consolidating', 923, 115, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('92fdd253-78cb-4719-bebd-8ac12d398f75', 'Secure', 924, 116, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('27777e4a-f0f2-48d2-8fa2-e601f78a7794', 'Growing', 922, 115, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a3dac6b6-9b14-4460-aff5-1471b23fd8e2', 'Growing', 922, 117, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3cfd68fa-f0cd-46b0-84b9-70104e7c4e98', 'Consolidating', 923, 117, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3f00ada5-7cb3-46b3-b51d-231e6ac236d4', 'Building', 921, 115, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b7d6a34f-5d78-4a1e-90ac-cbb7ece4fedb', 'Growth', 927, 115, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('10b50ca8-7d85-4445-bdcb-f7db12d8c718', 'Balanced', 926, 116, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0ced1a3d-2b00-4e04-8e35-9cf8e5a1ac41', 'Futurity Sectoral Indexed - Property', 8627, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6009faf4-7811-4810-835f-3b3ccca5b6eb', 'Growth', 11383, 530, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9eb0940c-8bf0-4e06-b71a-004d9c721103', 'Futurity Diversified Indexed - Balanced', 8616, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1d3309a4-4121-4467-b490-b154f1325b4f', 'Conservative', 11381, 530, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3d5f9d29-bd20-4804-87f8-9cc3e4a03e8c', 'Balanced', 11382, 530, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('dc6349df-08c1-4234-8df6-ae34b061a497', 'Sustainable Moderate', 15841, 451, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('25df8160-e039-4025-a3f3-967b923d0098', 'Futurity Sectoral Indexed - Australian Shares', 8624, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a110fa74-0dbc-4bad-8783-774bf9aa43af', 'Futurity Sectoral Active - International Fixed Income', 10687, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7420f6ad-b8ad-4946-ab0e-035292b7d282', 'Sustainable High Growth', 15838, 451, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('256d8654-7e96-44d5-a06e-175193b22217', 'Futurity Sectoral Indexed - International Shares', 8625, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d737a68c-c20f-4eec-bd30-2d000006457c', 'Futurity Diversified Active - High Growth - 2', 10694, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d5e68fb8-3dea-41b4-a582-04bfcff0fdb2', 'Conservative', 11381, 531, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('16b1719f-be9b-4e1c-9e75-5dbe0952218b', 'Sustainable High Growth', 15838, 452, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('88fe3833-5e54-4200-9472-db8c4b3b0198', 'Sustainable Growth', 6288, 244, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('52daddfe-4bc8-4eaf-9dbc-50a82dcca53f', 'Cash and Term Deposits', 6290, 244, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('605693ec-1c20-4ac0-8d37-fd2e77a1db10', 'Conservative', 6286, 244, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('65db698e-bacc-4985-8fea-9ad3bc507b73', 'Cash option', 481, 248, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('da16016c-2435-47ff-be82-b3a6d6a84349', 'Balanced Growth', 6271, 243, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5ee9dc6c-2324-4786-beb4-9d5bbe490ab2', 'Conservative', 6272, 243, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('cd3f9ad7-449b-46e3-b241-6aa0693b4918', 'High Growth', 6289, 244, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('8b590cd6-4083-4a38-b741-f9d9ba81d221', 'Property and Infrastructure', 6292, 244, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4f525786-d0d7-43e8-9c74-80077ecd6d38', 'Australian Listed Property', 484, 248, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7e3519ca-b948-457c-baf4-b0cc98685477', 'Indexed Balanced Growth', 6287, 244, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a7f14bcc-0d2a-4d85-9f41-0d8111debe69', 'Diversified Bonds', 6277, 243, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b681d75a-298e-4517-9c41-b48936d88eac', 'International Shares', 487, 248, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('79e4f573-c931-4ffd-aaec-a1d85d588117', 'Balanced Growth', 6285, 244, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('794779f2-8d89-48a6-8cf5-3ae7b5471bb5', 'High Growth', 941, 120, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9d290ebe-b3e2-4dfe-87df-a07021c1a69a', 'High Growth', 6275, 243, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5481f4dd-0d09-439e-81c0-5289df353815', 'Indexed Balanced Growth', 6273, 243, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('95bf3770-0b97-445f-bce3-fe64f8475d24', 'High Growth', 477, 248, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('52e03166-3c2c-4c94-a04a-b7e10304a917', 'Diversified Bonds', 6291, 244, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('250bb03e-03fc-49e2-bc88-05a6c74e80e6', 'Diversified Shares', 12895, 248, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('495fba0d-d33d-4d36-907c-0a37877a7c21', 'Moderate', 479, 248, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('510a48c5-ea1f-4304-b6d9-89fc7c64ed34', 'Conservative', 480, 248, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('942f88ba-f55f-41cb-acd8-01bfe9cfa45e', 'International Shares', 6293, 244, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('38e4f1b6-cef9-4d18-bd0a-3063e82ffe75', 'International Shares', 6279, 243, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('06de8520-a594-4d3d-bbbd-c48ab1e22035', 'Cash and Term Deposits', 6276, 243, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f7193cba-2e23-4fc7-a5e2-f451f7e59d84', 'Sustainable Growth', 6274, 243, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('15c64f31-5395-431e-96d3-027ae4acd4e7', 'International Fixed Interest (Hedged)', 483, 248, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('93526817-5ce5-4f4e-8e43-7c203192aac8', 'Property and Infrastructure', 6278, 243, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1e5bd3c2-358d-4a2a-9f01-05c39f568f1b', 'Australian Shares', 485, 248, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d664ec97-79ed-4546-a922-6a16d6ceaa9f', 'Australian Shares', 6280, 243, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4e1d08d3-7cb4-4313-93dc-c5eae909c17c', 'Growth', 478, 248, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f65a2488-a35e-42ec-939d-69d17676b50f', 'Australian Fixed Interest', 482, 248, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c2b112e1-f829-4211-bb9e-a30c0ed738ec', 'Aspire 2', 657, 380, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2a678f4f-796c-480c-b178-31d17e39b19d', 'Conservative-Balanced', 13858, 380, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('450dff8e-8761-4488-ad80-e1e9a01a6151', 'MIESF MySuper', 940, 121, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('56b0bf65-8def-4918-9dc9-8988d33b94ef', 'High Growth', 941, 121, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('fd32aa59-93ab-45e6-9485-d12e6a06007d', 'Balanced Index', 13862, 380, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1b716d47-9093-4f2b-a0bd-7b54d17ad0dc', 'MIESF MySuper', 940, 120, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('fefb7550-7a72-4b03-8c12-7b18e9a20d4a', 'Aspire 1', 656, 380, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('37839714-cd40-4f0c-ab9c-09324dc10193', 'Balanced Risk-Adjusted', 663, 380, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d8f8c751-5c87-4b34-a84f-7d7ffaa39480', 'Focus 3', 654, 380, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('19f84b8e-dd1b-4586-a47b-d95c36a0658b', 'High Growth', 13857, 380, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4b534ddb-c2ba-450d-86ad-85cc74a46776', 'Focus 2', 659, 380, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6beb7428-a4c7-474b-9014-05beb6f5b5ea', 'Balanced', 13870, 380, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e8748c84-d16e-445a-aa0d-4466c817e13c', 'Conservative', 13859, 380, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9366b0e5-9e12-4556-8b41-eaf7bb3387b7', 'Cash', 666, 380, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('903dd9bc-1fc9-4345-b4e7-786eee331751', 'Focus 1', 658, 380, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f92c4db3-1885-4fb9-aaff-423a2a46d3bf', 'Bonds Index', 13868, 380, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ff9b0825-3673-494a-9419-18c20728cc9d', 'Australian Shares Index', 13863, 380, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4a681556-6132-4c83-b5e6-073707f08e29', 'Balanced', 14209, 560, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('fff0f1c0-77dc-4496-910d-4da76480fb67', 'Growth', 14208, 560, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('25db45b1-d5cb-45ac-9f7f-7ad336c59879', 'Defined Benefit', 15041, 570, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a2bcd717-80fc-403a-9f42-5a9870a58643', 'High Growth', 14207, 560, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e6a14777-a87b-4629-86e8-faa42df668e8', 'High Growth Index', 13861, 78, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e2f13504-0b69-4d92-8ddd-68c8b2bf8657', 'Australian Shares', 675, 80, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2ed2f1ca-6fee-4a9f-b3a4-bb13e3e8adbb', 'Sustainable Growth', 6254, 381, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6031436c-a0d1-4dfc-bd7a-4e9dc8f46dd9', 'Growth Plus', 14134, 80, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('30b6b362-bc16-412b-b808-10095c39d747', 'Australian Shares', 693, 389, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('210d5996-27bf-4360-856d-9ec6b1053b26', 'Growth', 670, 80, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f7978b66-f2bb-4d78-b6d6-490f1c233c53', 'Cash', 674, 80, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c8fad575-9c6f-4ee7-a0b1-63720130a8db', 'High Growth Index', 13861, 380, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c9c9d4a7-e025-4455-aa84-f6eab1e9e03f', 'High Growth', 29, 381, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c612eae0-c3ce-41e4-b878-815b118850d8', 'Growth', 12765, 542, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a82dfe02-99e0-4d72-bec3-c2e352123d15', 'Managed', 12768, 542, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9d5609d9-fe73-444a-ad5a-b9673a4bf4f8', 'Conservative', 13843, 559, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3f61e95a-9b7a-4116-a07b-f95c53986c95', 'Defined Benefit', 12897, 546, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d737a965-2839-43d9-a356-85b37bfdfbf5', 'Property', 13849, 559, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('acf0f922-48d7-4e17-baf0-d46936c32e4c', 'Raiz Property 10 Portfolio', 15988, 585, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('76a29d05-62c3-487a-9ed9-e6b28d2818ec', 'Shielded', 13850, 559, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f84488df-dfc9-4fb6-a649-0141f20c3d2c', 'All Growth', 16224, 590, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('bcb92e3d-5463-4085-9871-37c51820a938', 'Raiz Moderately Conservative Portfolio', 15983, 585, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e39061e5-8335-4c4c-8582-3a45ea8aadba', 'Diversified Growth', 13845, 559, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('accfc122-6688-4468-bac4-b3031ca9e08e', 'Salaam Balanced', 13554, 558, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('68a30454-7bc7-40f4-9f87-c4cb96fb2202', 'Salaam Growth', 13555, 558, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('195e76f3-3cea-42c7-b54f-668d8d882751', 'Balanced Growth', 16225, 590, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1d011048-dafd-4635-8ecf-08f6d60063d5', 'Wholesale Global Equity Fund', 13853, 559, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('136cbc6b-ed3b-4201-8d5c-0d89a4b0b24a', 'Lifestream Guaranteed Income', 16971, 597, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('04389970-6643-416a-9160-2658c41d4ac8', 'Australian Equities 2', 13840, 559, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('76b78783-9734-474c-aab4-771e22f05337', 'Raiz Aggressive Portfolio', 15986, 585, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('77598c61-e8fd-4a09-95b4-7b75e4e5d2b0', 'High Growth', 12767, 542, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c6ea1261-c6cf-4668-b8c8-9a404d6eb2bb', 'Raiz Moderately Aggressive Portfolio', 15985, 585, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7e10568b-a01e-477b-bb29-0f0e0ecb1d02', 'Diversified Fixed Interest', 13844, 559, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('43de88c9-be38-464f-89e7-572b1458afc5', 'Specialist International Share', 13851, 559, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9edc05ce-de72-4d6d-b0d5-ec276e0439fb', 'Diversified High Growth', 13846, 559, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('8aa9d42f-d00c-4f0c-b2ac-ad39d21189b9', 'Raiz Conservative Portfolio', 15982, 585, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ecdba69f-4cc7-4d21-8a0b-4f70fd998a41', 'Australian Equities 3', 13841, 559, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f0113f4f-e77a-495f-a9b0-20c2220a348a', 'Guaranteed', 12766, 542, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1bcf52bc-002c-4727-8776-8304aa6d9921', 'Raiz Moderate Portfolio', 15984, 585, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e0a511f4-48dc-453d-8a45-8078aab8029f', 'Raiz Property 30 Portfolio', 15989, 585, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('87e6d91c-df1e-41c6-9046-658eabaa323d', 'Raiz Emerald Portfolio', 15987, 585, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('be9af345-fc52-4940-b15e-dd476526ce0a', 'Pre-mixed Balanced', 13848, 559, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6b1b1e7c-d99d-4a73-8775-c125d553cc11', 'Cash', 13842, 559, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0f607486-b167-4126-a9c5-25e1a97adce9', 'Moderate Growth', 13847, 559, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e8e1524b-20ed-459d-83d3-2d5b05e63fd0', 'Conservative', 16226, 590, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f605b201-b135-49f1-9d73-e51e76d4626e', 'Australian Equities', 13839, 559, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a600c140-3c38-468f-8a97-686be6d6cf2d', 'Salaam Defensive', 13553, 558, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3c876c9a-9ae4-4709-ae7a-c17903487bf9', 'Unlisted Assets', 13867, 78, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1a08a4a1-b7d8-4da4-ab8a-14b0223f21ef', 'Outlook', 655, 78, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('44291bad-1ce1-4fb8-a37d-2a2eb66decb6', 'Sustain 2', 661, 78, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('80cad4c4-c454-4dce-9b77-54182f95006a', 'Socially Conscious Balanced', 13860, 78, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6014f2f1-05b4-49d6-a7c6-7f859472e855', 'International Shares Index', 13864, 78, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('702675e5-a971-443d-80d8-593a791b63ec', 'International Shares Unhedged Index', 13865, 78, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('081287fb-16bd-4f9e-9ba6-5197963d0d69', 'Sustain 1', 660, 78, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('717c3f6d-4b0d-4b37-bb1e-3f1b7c46a0f6', 'Listed Property Index', 13866, 78, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2b371bd9-4da2-4d41-9147-f846facba5ac', 'Sustain 3', 13856, 78, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('8f847905-302f-4383-aba9-e1391d910917', 'Stable', 756, 497, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f61ddba4-bb10-45db-b529-956b682fbb7e', 'MySuper Growth', 13067, 577, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('bc523af9-f650-45a3-9cc3-94eb04a91c4e', 'Defined Benefit', 9843, 478, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2e487674-4697-4332-bd4c-5ee206daad26', 'International Fixed Interest (Hedged)', 13077, 577, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d1703732-ceee-424d-a418-e9e610f6d6d8', 'Australian Sustainability Leaders', 13084, 462, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('086abe95-2504-4b0d-8561-fefac63590da', 'Capital Defensive', 757, 497, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b220cf2d-a43d-4a9c-9635-9753d27a940a', 'Stable', 11230, 496, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5d1f6a0e-8fe1-44d1-ac44-e49ee8a905fc', 'Global Sustainability Leaders (hedged)', 13083, 462, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9ec51fbf-76fd-43c0-9c85-182fe2461fac', 'Australian Shares', 13072, 462, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e15100ba-d35a-40a1-a818-3019eda0cb56', 'Global Healthcare', 13081, 577, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('57533ef2-38b5-4c4a-a7d1-77d99ebd9c04', 'Defined Benefit', 9844, 479, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9c128300-4db3-49a5-8303-7dfa9a0fcd6d', 'Moderate', 13069, 462, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('17d1b756-066a-4991-a1cf-1edf0bb8533a', 'Growth Strategy', 9845, 479, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('82cd146b-076d-4e00-acfd-76c26258b6d9', 'Australian Shares', 13072, 577, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('567dc1a5-ccf0-4b1d-a5d3-1a9570884899', 'High Growth', 13071, 462, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9c5cdead-9994-4118-a057-ac225c7f75e4', 'Balanced Strategy', 9846, 479, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e4bcba60-a73b-4598-aa3a-f93257defd6a', 'Conservative Strategy', 9847, 479, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('10519391-d73f-40d1-ba10-f460d1d6b4c5', 'Cash', 13078, 462, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('04bcdf79-7c9b-4dbe-9cc0-44168885a7f2', 'Socially Responsible', 11227, 496, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('741e6b69-d892-4d5c-a727-32752b7423c7', 'Cash', 11232, 496, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3132e6d5-a58f-4ea1-8c29-c31a17ca632c', 'Australian Fixed Interest', 13076, 462, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f27be741-8b7b-42f1-9fd9-abf34aa73dd4', 'Socially Responsible', 752, 497, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('57a9c00e-829f-4b4a-a5dc-a85455ffcf49', 'Balanced', 11228, 496, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('8c983524-8487-41ae-865e-f03aa0c372a5', 'Global Sustainability Leaders (unhedged)', 13082, 462, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('30b22239-0a67-4d0f-9e7d-aa659e92ad10', 'Australian Sustainability Leaders', 13084, 577, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('04e8d1ff-a79d-414a-b1b8-7a06ab623efa', 'Moderate', 755, 497, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('894fe39a-3ddd-4bdc-b9ce-a6219fa32161', 'Gold', 13085, 577, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0c30d73c-f282-4bb5-97d1-f3a121ce27d4', 'High Growth', 13071, 577, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ee470204-b8cd-4527-891d-bffb97781fc8', 'Gold', 13085, 462, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b368296b-d756-44ca-869e-bb884582ad97', 'Growth', 13070, 577, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a7944bae-eaca-4862-9245-a0d5599d74a0', 'Cash Strategy', 9848, 479, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6e7ae386-2229-400b-8cd6-31da152eb065', 'Asia Tech Tigers', 13080, 577, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('fe54c4e5-efcf-439b-9e1a-a0a6d1333dae', 'Conservative', 13068, 462, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('deb60f30-7c90-4350-b507-cd4408137ef3', 'Moderate', 13069, 577, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6540d608-877c-4b29-b1c2-ad3f9adbcb50', 'US Tech Giants', 13079, 577, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ffea9c6b-5505-41af-a6cd-45042678163f', 'US Tech Giants', 13079, 462, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('27f54580-935a-4719-ad96-3db8e33897e7', 'Asia Tech Tigers', 13080, 462, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('cf9d1427-fbdd-4296-974d-1d46b69bc24e', 'Cash', 758, 497, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('170904ac-4d01-46e8-8409-ef9edcdbe410', 'Australian Listed Property', 13075, 577, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ae20f934-f91e-4fb3-b233-fcf8f0f18c49', 'International Shares', 13073, 577, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('49fd9b25-9fd4-4383-860a-2abef76ffbab', 'High Growth', 11226, 496, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('40a45e2d-e8a2-41dc-a3d6-a094ce17dce1', 'MySuper Growth', 13067, 462, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3e7d6190-f033-4607-b834-7ab1518cd417', 'Global Sustainability Leaders (hedged)', 13083, 577, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('8ed006bf-7a14-4115-96db-76834ec26af8', 'Conservative', 13068, 577, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('241606fa-c00d-45c9-92d4-dd28cd172937', 'Cash', 13078, 577, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('96a72ce9-45b5-47f4-ad1a-1eae3903d611', 'International Fixed Interest (Hedged)', 13077, 462, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ca4d3872-fa91-4c13-adc9-209412af933d', 'Growth', 13070, 462, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('58cc70c6-5688-405e-a840-b6e72ce02d08', 'Global Fixed Interest (hedged)', 10524, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7145f69e-ffb5-4454-8e55-860bb0d3128b', 'Cash', 10525, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3b575066-e46d-44ac-a762-c0b50e1053ee', 'Australian Fixed Interest', 10523, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9e57be4c-df99-4aba-9d2c-39d3a2099d0f', 'Australian Shares', 10520, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0bf9b1ba-a26c-4602-af4b-cecd35049b56', 'Conservative', 10519, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('167deaa9-a32a-4c83-b59d-1e11fd45dd12', 'Australian Shares', 10520, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9e53eddd-7d1f-4f56-ad8b-f66ceeb78eae', 'Ethically Conscious Growth', 10516, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4e3359bf-8561-41fe-ad77-f144d3af27f1', 'Australian Shares', 10520, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9dd68e94-1fca-4d60-b7b6-c2b302babe93', 'Australian Fixed Interest', 10523, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e4e2def4-7860-45c5-a8af-6bc67fda59dc', 'Global Fixed Interest (hedged)', 10524, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6bb6581e-5eb9-4a58-ae8c-3986853981be', 'Balanced', 10518, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ae36f0da-d1d6-4e9f-b392-3c306be99e0f', 'Balanced', 10518, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d061668b-6fa6-4130-806c-eb8fee4673f6', 'Conservative', 10519, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c02c8bb8-3eae-493f-b27f-b565eb9975fe', 'Australian Fixed Interest', 10523, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('074eedd5-bd4c-4c43-9eb7-da88f51540ca', 'Balanced', 10518, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('537ec5bb-c7df-4a6b-bd6f-0b8f3fe73825', 'Cash', 10525, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9e9a7c22-37c1-492b-904d-6933fba9db06', 'Cash', 10525, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9f074a23-b9d8-44f6-a8ae-0da580471d9d', 'Ethically Conscious Growth', 10516, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('fa691c2b-4285-4820-a39f-63e7426b780b', 'Ethically Conscious Growth', 10516, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b60b1bd2-2a9b-4135-8175-d933e120a0f0', 'Conservative', 10519, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('73451759-c6c1-4c17-a3c2-e35ede3f6cdc', 'Lifecycle 67', 10769, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('80909f67-cb86-40a7-8cf1-a7e63e11e5aa', 'Lifecycle 58', 10760, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7a9a60ba-dc75-40e5-9979-e6ea1c2fca6d', 'Sustainable Alternatives Growth', 16277, 592, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('789a1007-2cf6-41b4-8f53-33b53346b59d', 'High Growth', 10515, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('8efd7340-9f2e-4ed1-8af8-5639d198b64e', 'Growth', 10517, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ae12a9c0-0138-4dd4-8b6a-a26c8e80e606', 'Lifecycle 64', 10766, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f6cd6d2b-bae9-4038-a50b-2d1737e68302', 'International Shares', 10521, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6d083153-2d50-47c7-bb33-96e91e740b58', 'Lifecycle 50', 10752, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f053ba97-3c48-47b2-9b4b-7d0c74fdb6e9', 'Lifecycle 59', 10761, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2fd22ad4-9e0d-4c73-9bf5-9e5b5b374511', 'Lifecycle 49', 10751, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('823299d7-6684-4676-98ea-c6016da313d3', 'Lifecycle 53', 10755, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('911748b3-fd1c-4240-99d0-f764f627cc41', 'Lifecycle 53', 10755, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d2ca2eb8-5264-4798-9920-ebbdd8d3caf0', 'Lifecycle 55', 10757, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c7fa0336-67b9-4fb0-bd59-cc7c0f50aad7', 'Lifecycle 55', 10757, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c47fc21c-ded8-46a3-891a-1d4508ace87c', 'Lifecycle 52', 10754, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f51ee1b3-05ed-4a4f-9173-e296417b4ab4', 'Lifecycle 54', 10756, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('320bfd99-dc6c-4ff3-98d1-0fbba4439824', 'Gender Equity Australian Shares', 16278, 592, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('11241dd9-7f95-43a1-8a14-d2f1be34ccce', 'High Growth', 10515, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('094839ef-e58a-4aa8-934a-2bbb0e413906', 'Lifecycle 62', 10764, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('86a89c67-0ed6-4525-b84f-03169993f1ba', 'Lifecycle 54', 10756, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ca056ca2-d478-41a7-92e4-bcbe3f1d0085', 'Lifecycle 57', 10759, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f447bb1a-7fd0-4f88-9ae9-95793cebe759', 'Lifecycle 61', 10763, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('441eff20-3273-452b-b0fe-0084d9952b2a', 'Lifecycle 57', 10759, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f53dc074-ae6b-4827-9c92-5f23ffefbebb', 'Lifecycle 51', 10753, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('bbc87894-559f-4969-9dc3-112bca56d847', 'Lifecycle 49', 10751, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ef102d4a-d7fd-4947-8b5c-fb3b67b50a5d', 'Lifecycle 65', 10767, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c9a79d04-1d9f-4acd-a530-d35fc3fcfa1f', 'Lifecycle 59', 10761, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3e0f6fb2-2296-4dbd-bfdc-e0043541c847', 'Sustainable Balanced Growth', 16275, 592, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('143100e6-5f8c-4e3a-8bf2-50b25beedcd4', 'Lifecycle 64', 10766, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('78aec996-ae8d-4bb1-86db-a7bb3ec1cb3c', 'Glidepath: Destination', 649, 76, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('45bc95c9-3b3c-4284-817b-a8fd544cdbc6', 'Fixed Interest', 372, 43, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('990dffb3-7393-438a-8170-716742eac643', 'Indexed Conservative', 15424, 53, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('53d79531-b500-43f6-b125-7cc9e3bb099d', 'Balanced plan', 416, 50, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d24cf4a3-415c-49f4-9020-dd0dc46a4a43', 'Focus 2', 659, 78, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a38363ff-762b-4d97-a334-d7e5e6a33efc', 'Balanced', 305, 36, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('06bbcf76-3bb4-4f9f-889a-261af94f9874', 'Fixed Interest', 434, 49, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('87ddf737-d256-4fed-ac4a-9817e8661346', 'Conservative plan', 438, 48, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d9f7918d-ab7d-4c11-96df-6a0cd8ec9d9e', 'Conservative', 514, 58, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9d454ec3-8dbd-4493-b2f9-5b65d6160b6a', 'Conservative', 13859, 78, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d1eda4d8-16a6-4120-888e-5279b304d6e3', 'Overseas Shares', 594, 69, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c8065f8f-4b21-4669-847d-7866ef86158f', 'Stable', 521, 61, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7e479e9c-eba4-47b4-9d38-96c390d57e03', 'Balanced', 405, 47, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('132903d9-35cf-47b2-8d8d-1e67a0af073c', 'International Shares', 374, 43, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('85ca7064-0dca-4819-ac1e-e7ed7a2cdbf0', 'Australian Shares', 524, 60, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0f68d6ee-1964-4ee4-b746-edc948e9cfc2', 'Conservative Growth (default)', 242, 28, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a855fdbf-dcb9-4b7e-89e9-fad694876bf1', 'Diversified Fixed Interest', 297, 34, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d46f31fe-ddee-4bb6-9f21-f76a1349cb28', 'Cash', 460, 53, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4a911a15-e6b2-4590-b6b6-93dd6e757124', 'Accumulator', 10551, 57, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e13fb8ea-6773-433d-abde-d3eeb80f122f', 'Property TTR', 451, 51, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e0e09fdc-ee70-4d50-9dda-21fb62a7384d', 'High Growth', 212, 64, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('483ae7b3-acb2-4150-a1a1-0afb3057d2ff', 'Balanced', 458, 52, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3ba89b6a-b95b-4026-aae6-f84a55a4a810', 'My West State Super plan', 428, 49, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4e49cb09-6445-4c15-9bae-2e4d2e0396b7', 'Indexed Defensive', 12151, 52, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ae19fa39-4858-40e7-bf79-a3f1860bca6a', 'Conservative', 455, 53, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4df8fc7b-5792-4982-8c54-c64d6663e96c', 'Balanced', 13870, 78, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3b69ab6e-9046-4614-a75a-8d1664346002', 'Property', 1003, 70, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('094b15bb-f2e8-43e7-b770-f170b2e746d4', 'Cash', 410, 47, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('aa0e0c89-9695-4360-aaa7-daef3c6b793f', 'Indexed Defensive', 12151, 53, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('09cc3be7-dc6b-43f4-8ff9-a3dde41e6df4', 'Conservative Balanced', 94, 17, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('66f9058a-6f7b-410e-b316-fa8be517cd46', 'Defined Benefit Strategy', 510, 59, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f7079432-1a92-4cf3-ac3a-fef6404928e4', 'Diversified Fixed Interest', 526, 61, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('edb6b591-88da-4862-b380-35322076d686', 'Defensive', 318, 38, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3cb321fa-acbf-4de8-a63e-8099902d4dae', 'Shares Plus', 404, 47, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('698a4ab5-9fad-432e-aded-d23bdcdc1eac', 'Aggressive Growth', 60, 14, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b405b1dc-aae7-4f1b-95de-dc8ef2d0f322', 'Australian Shares', 431, 49, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('579d5cb0-ea13-4f8b-ba93-82d91d92c629', 'Defined Benefit Strategy', 510, 58, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6e5b6beb-56d4-41ba-8ae1-a927f1049e44', 'Australian Shares', 464, 52, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('95857de9-6590-435a-a9a4-b170ee54d9e2', 'High Growth', 509, 59, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e8e15e69-a7eb-43b8-ba03-a1f003e3a478', 'Indexed Diversified', 9335, 28, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('92d4853b-5850-441a-be11-008cfd6d3562', 'Conservative', 241, 28, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4b465d01-763c-4ed3-ba87-dc14e1915afe', 'Diversified Shares', 12895, 54, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d5918213-60ee-4f38-a112-12b19e1134f4', 'Conservative Balanced', 513, 59, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0f4f55cb-d666-4707-83a6-afedcf8fdd44', 'Thrifty', 6359, 76, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('fb3512a6-69d6-4dc7-b262-84a4e99dcaa6', 'Indexed Growth', 620, 72, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('14bbaf66-13db-4845-a5a4-592b7ec95e4f', 'Socially Conscious Balanced', 735, 76, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('482a02cf-3fe4-4768-bff8-0d3234909ca1', 'High Growth', 591, 69, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c45b813a-dd1c-4627-a704-90f219228202', 'Smoothed', 369, 43, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('811abe25-3570-4adb-8011-914e19623c4d', 'Balanced', 26, 12, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('10a7d2eb-5fcd-4a35-9813-6f2b3c0c2dfa', 'Conservative plan', 438, 51, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('27d102a2-6a1c-4132-b201-4c92f0d2cfa0', 'Indexed High Growth', 12150, 52, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c1c220c9-1e65-4814-b4c6-ed21f8184351', 'Fixed Interest TTR', 452, 51, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('60e5cb28-e2fb-478c-9486-53f38f5662be', 'Conservative balanced', 501, 55, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('04b901ba-1d03-496e-9a57-26057a88ce98', 'Property', 525, 61, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e5fffdb9-5653-4a23-86dd-d948134114b6', 'Balanced', 494, 56, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f8400c37-2079-443d-af62-144805740513', 'Managed Growth', 630, 73, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('19b8a218-0768-442d-aba9-edd698599147', 'Cash', 444, 48, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('19d7491d-00a5-4329-80b1-11cd9cbafe91', 'Balanced', 313, 38, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('691615ce-9752-4158-bfca-50d554823193', 'Conservative Balanced', 411, 47, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('dab1bd59-ef21-4238-951a-58e1887def37', 'Indexed Growth', 14908, 52, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('87120140-3afe-49b2-ba30-11e91bb583c7', 'Balanced', 458, 53, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c6c18437-80e0-4448-9e39-dfafc04d5fcc', 'Alternatives', 997, 13, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5b7081f4-30dd-479b-a759-f7a56d93bb6c', 'Capital Stable', 288, 34, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('67b10d09-82ed-48b3-804b-de706de6c71e', 'Capital Stable', 25, 12, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1b89b310-c67a-4910-bbcf-8a8be55e3ceb', 'Defensive', 12149, 52, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('012d9c48-6580-4477-ac09-58fef1e3e2ad', 'High Growth', 244, 28, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('88c0ebbe-793f-4474-a10d-d77fbff1e428', 'Conservative', 490, 56, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c0b23159-e075-407d-9554-d82a6c00f42e', 'Australian Shares', 635, 74, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f6356c95-c1d9-41f0-aad3-7756b8809f65', 'Cash', 149, 21, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a34a4121-72aa-443c-bc72-25a7ab08f38f', 'Growth plan', 436, 51, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a1b18cc3-ae35-4367-a74b-966d8bc9f83b', 'MySuper', 629, 73, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b021c49b-50aa-44a5-af37-163fcafdb427', 'Cash', 298, 34, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9d620421-1715-4605-8591-bb49753c470a', 'Balanced', 512, 59, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('690c798b-1dd3-4005-b963-c603f88cddc0', 'Diversified Bonds', 866, 104, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('099769ec-a030-47b6-b0fc-eab362c83881', 'Growth', 857, 104, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9891273b-7a3a-460c-91b1-93c4e066e3b3', 'Just Shares', 862, 104, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('074030cb-82c2-4151-965f-dc769b7f6d4b', 'Just Shares', 862, 103, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d501569b-de85-4458-9c30-82fe4369999d', 'Innovation and Disruption', 863, 104, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('78ed2fcc-5622-4129-8649-93b3687b48d6', 'Just Shares', 862, 102, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('115974be-eb81-4155-a1d3-5b8d98358607', 'International Equities', 865, 104, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7ddb3798-ea62-4f61-ba5f-9b824f05553b', 'International Equities', 865, 102, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a350a785-5730-49c9-b86f-c46cfb25abc8', 'International Equities', 865, 103, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7520b185-935f-4550-8ac5-a5db3ad1b167', 'Passive Moderate', 11521, 533, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('109071f8-eb43-4db8-b9db-d0d1ae00dcce', 'Defined Benefit', 15039, 568, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f8738b59-92d0-43be-a002-556054086134', 'Moderate', 11519, 533, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('574e7d5c-8249-42a5-9712-3d00032d1cd8', 'Balanced', 11522, 533, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3757997f-7756-4675-ab9f-af552129d469', 'Growth', 11523, 533, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('10443a35-1ae2-4028-845a-6f5a621aae29', 'Passive Growth', 11524, 533, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7dbb0fd2-cee4-40ba-b960-cec1064d4eb6', 'Passive High Growth', 11526, 533, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('426324a8-d3fa-415b-b8f1-64a949b80658', 'High Growth', 11525, 533, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('983d8f9c-5ad7-464c-afbf-ef548dc98aa1', 'Cash', 11518, 533, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b8d6fdf6-6317-4b1e-bf6e-9c042cf711bb', 'Passive Balanced', 11520, 533, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a65dbc85-a1b9-4a9e-aed9-912a102130fd', 'Property', 611, 71, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9f73e69a-02e9-40bd-9654-afbdba8e2449', 'International Shares', 476, 53, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('db5438ec-5bc9-4681-98d2-589eff0b891b', 'Australian Shares', 524, 61, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('796c1346-d9c9-4af4-a47d-505d9561e265', 'Overseas Shares', 594, 70, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a32f4a1c-b29c-467c-8893-60beb8d56cd1', 'Australian shares', 506, 56, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a70c40a2-8b6a-4022-a11f-7e99ab4ba933', 'Growth Plus', 9515, 27, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('615f9afe-eca3-4afe-b914-9efeb5d2106d', 'Australian Shares – Indexed', 9150, 52, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d8f75ab4-48ff-41ed-acd5-994abd773ab9', 'Sustainable Balanced Plan', 13576, 49, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('53949f7d-6231-413a-982c-bd908ff56f8a', 'International Shares - Index (Hedged)', 742, 76, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('68e06d5e-c07f-4f47-ae81-b3a90e6d5a95', 'Indexed Diversified', 96, 17, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('fd8ef682-2cf5-4762-9d1e-0f4ec827da39', 'Regional Defined Benefits Fund', 16347, 60, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0aa99c77-e5ee-44a1-baac-903af5206728', 'Growth', 496, 56, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0ca7dba0-7a70-48e9-9cd2-6224c97331ea', 'Capital Stable', 56, 13, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('203c53fa-8eba-4d1c-988e-c2076f566f03', 'Australian Shares', 440, 48, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('189876d6-8e95-42c4-bbd8-6b162477edbb', 'Unlisted Assets', 736, 76, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('8838994c-7cd9-4d09-937e-001d1b293275', 'Stable', 95, 17, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4c6a0079-5273-433b-a912-8d34deac1f3d', 'Cash', 406, 47, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('032842e3-ca45-4f42-a734-ba84b4e810b2', 'Conservative Balanced', 113, 18, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b972546a-1361-408a-8175-09b2346ba8bd', 'Fixed Interest', 185, 22, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e9bf6925-da11-4057-a4f8-88f74f8c05c0', 'Growth', 233, 27, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1d8a3134-6144-43a7-bec8-d905a4386dc7', 'Cash', 319, 37, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('42468b51-4488-45f1-ac1a-beae6d03dba9', 'Bonds Index', 13868, 78, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('244de7f8-d163-4124-8db9-04345d546111', 'Overseas Shares', 9589, 26, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7195c7fa-4bc3-4d82-921f-b512ee835c14', 'Conservative-Balanced', 737, 76, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('051423f3-5282-49bb-8acc-d3d03488d89b', 'Fixed Interest', 150, 21, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0b2e753f-3a96-4239-8ece-8378e0e62979', 'Growth', 459, 53, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2f8f5c09-d8db-45a2-8e95-103def879ac9', 'Balanced', 289, 34, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b44c99ae-ceab-48f7-a4c2-9d0fde5d0945', 'Growth Plus', 9587, 28, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c7c168e5-a56c-4837-8630-4f9c96e48884', 'Ethical Diversified', 321, 37, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d027893a-95c5-4028-8d08-f0737be2a399', 'Bonds+', 461, 52, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('37ecae6b-de81-4680-aa11-e4bd9c634c0b', 'Cash Savings', 216, 28, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a8b38795-cf0b-409d-be08-bfc605d3cf8a', 'Growth', 24, 12, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3153627f-4df3-4931-bc48-3370c90a5e2f', 'Infrastructure', 625, 72, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5bf9574a-3a22-49d7-8bfe-089296631336', 'High Growth', 732, 76, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('15baf8f1-d124-4471-b5f2-332ebcaafb78', 'International Shares', 476, 52, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('91e0761e-2c4c-4df2-8b31-50aee784d2c2', 'Cash', 527, 61, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('889ef47c-f533-4c9b-a16c-f9c8b544522b', 'Balanced', 651, 76, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c59b79d7-3003-416d-8ff0-22d5b0e888cc', 'MySuper balanced', 503, 56, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1adf42a5-4318-4050-8926-cc7d0bddfdbb', 'Balanced', 733, 76, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('79a7d0e5-fdd9-4eb2-8efe-c31756f7889d', 'Balanced', 494, 55, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ae2514ec-2e22-47d8-8c1a-46e1137a17fa', 'Conservative', 632, 73, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('29ca6592-c271-4299-b24e-94f3a874d3ba', 'Alternative Growth', 147, 21, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('31452028-c749-4768-a69d-848db1993d1e', 'Diversified Bonds', 627, 72, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('25f3491e-2123-473b-86a1-f0c653aa90d7', 'Conservative Balanced', 9981, 60, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7badac48-efae-4105-9d9f-89ae0251e595', 'Australian shares', 506, 55, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f3bf50c1-ac82-417e-9ca8-4bd9e65db04b', 'Cash', 640, 75, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1e48f4ca-9acf-4b2c-ab7a-3fec52ff52d1', 'Index Diversified', 11295, 34, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('04497ee2-89eb-447c-a975-d2a787b93152', 'Balanced Growth', 320, 37, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7ff8ed78-894f-4b96-af6d-7146417752a2', 'Conservative', 215, 28, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c1d8cdea-39a3-497b-8ce2-f5f54ad98fd1', 'Shares Only', 322, 38, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2307b778-41fc-4cd6-9eb7-2645c6a442fc', 'Conservative plan TTR', 447, 51, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('052344a7-797c-4938-b7cc-7cb6d6d8b13b', 'Diversified Fixed Interest', 201, 23, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f603d5e9-056e-487f-84a9-94195fc6cd53', 'Stable', 521, 60, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3424d1f8-69b3-4d04-9327-6739e749c0dd', 'Australian Shares', 623, 72, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9b431181-40b4-4a19-81b3-ecbf58aefca6', 'Indexed High Growth', 12150, 53, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ab648070-2d3e-46cb-8032-253440de75d9', 'High Growth', 999, 70, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('16b19264-314c-4409-84f9-33d830018a30', 'Balanced plan TTR', 446, 51, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9f4bd566-cd19-45c2-870e-4267112d5381', 'High Growth Index', 13855, 76, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('273f21f5-f96b-4478-a9b1-b8e447445b1e', 'Enhanced Cash', 500, 56, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('59934336-2752-480a-a9fb-874f17f37d4b', 'Growth Plus', 9587, 64, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('24304cfe-3e72-4e7e-9a7c-868359ab195c', 'Growth', 303, 36, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a869680d-4d5d-4c04-b18e-51cb3630b2e8', 'Diversified Bonds', 612, 71, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e64e9d2d-05a5-4c48-b0dd-41108889eba2', 'Conservative Balanced', 513, 58, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ec119aed-7b3d-4a4b-b16a-edf59e0c0da3', 'Bonds - Indexed', 9149, 52, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('50f4c8bb-082c-4f67-b240-b83537643802', 'Cash Savings', 216, 64, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('aba4478f-320d-4151-80ae-2bfb5acdb015', 'Balanced', 54, 13, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e95a7da6-3f08-4e45-ba90-7657868161b4', 'Overseas Shares', 199, 23, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ee2a49d3-7e24-42d8-946c-e1d27c59400b', 'Balanced Risk-Adjusted', 663, 78, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('13f5d477-3a3d-47b7-908a-152ebb0e603b', 'Diversified', 615, 72, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0394503e-95f8-40b0-9498-1a885f556e99', 'Indexed Growth', 606, 71, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('82ffc70b-a2ef-4bab-a441-0946ecfcaece', 'Indexed Balanced', 457, 52, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c0155d62-1b58-4793-84fc-cb41d69c9437', 'Australian Shares', 9590, 28, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('abec73e6-53d6-4c83-a995-dc2532a8eb03', 'Conservative Growth', 214, 26, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('fb0f09da-6033-46b5-8f7a-1b2916f4fc16', 'Conservative plan', 429, 49, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e36bfb9e-9c8d-4785-bdee-b84653f4cd18', 'Balanced Growth', 290, 34, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('97c314e4-ca74-4836-bf19-a86c472e7f9a', 'Property', 421, 50, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('be009096-af32-41f6-b987-366cd9606141', 'Overseas shares', 507, 55, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('8dc03ed6-073f-4831-aaf1-df72ff102dba', 'Diversified Fixed Interest', 526, 60, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('466ea245-3f4a-4939-beeb-62c55f8cdb97', 'Growth', 650, 76, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('fddb9822-59c3-4876-919b-72895fae756a', 'Balanced Risk-Adjusted', 13854, 76, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0a5ab71c-ec3c-4db5-bd0f-cbd80c2b2d59', 'International Shares', 624, 72, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('29c11ba7-e625-4ab0-b5af-c4c98dfa6536', 'Fixed Interest', 422, 50, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6a646d7c-3693-4292-9c52-6d47265fb653', 'Indexed Diversified', 115, 18, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('65511d0d-fcae-4715-a750-0c9335ca676f', 'Balanced', 111, 18, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2c12d876-ec85-40f7-ba4f-17552ef11de8', 'Stable', 454, 52, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1f983597-a3c5-40bd-818d-e468d5a77453', 'Conservative Growth', 214, 28, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1b0a107e-2590-4d64-ad7b-fba265d21861', 'Overseas Shares', 9336, 28, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f2c34ee8-3e01-44da-ac3d-23bc795a2355', 'MySuper', 516, 61, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2d70c24f-9143-4a05-afa8-ec5a58375279', 'Growth', 315, 37, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('bd528e08-cd34-42f9-a0a3-a665e3134756', 'Balanced Socially responsible', 504, 55, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b7ef2ca9-96a9-485e-ac0a-69ea70c9eba8', 'Capital Stable', 194, 23, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('356077ea-398a-490f-bd2c-d1d2132406d1', 'Balanced', 405, 46, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('78cfb8a5-4cf6-4b8e-9051-ea4643efcfa0', 'High Growth', 12148, 53, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a4ee7586-30d5-4005-a7f3-e5aab1f7d244', 'Capital Guaranteed', 178, 22, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a4c07b1e-3250-4334-a6bd-0eeb1b73ca64', 'Fixed Interest', 311, 36, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e8327b6f-f87d-47e5-a4a9-aebc1b75feec', 'Socially Aware', 93, 17, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5f77a8c2-727c-404e-a69e-f46d3c91a8d9', 'International Shares', 441, 51, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('545d0d04-28da-47c2-ba47-97892faefb2e', 'Overseas Shares', 9589, 64, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ff8accec-35fa-459b-905c-5c6727f0b3c8', 'Balanced', 409, 47, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c3c4a06f-a402-4a2b-8c45-c62e6be2df8b', 'Conservative Growth', 232, 27, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7ee79f51-08aa-4b8c-b67e-99c801bba394', 'Overseas shares - Indexed', 38, 12, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0307a272-74be-4865-83b3-341933fa3578', 'Aggressive', 643, 75, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('66be730c-c261-43c0-969b-89f5d60f0f8c', 'Cash option', 481, 54, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2e73a23d-b8fc-49fc-a5ec-2c8ca6ba9927', 'Sustainable Growth', 6254, 12, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('19f4f22c-85c0-4b36-b3cf-89e702bfed93', 'Balanced plan', 437, 48, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7df85d6f-ca19-4858-8ad5-d242182ddaab', 'Australian Shares Index', 13863, 78, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('8ab39506-ddca-49ec-8690-59edd4455b23', 'International Shares - Index (unhedged)', 743, 76, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0d490bb3-bcea-4fdc-b1ac-428572aab543', 'Australian Shares', 187, 22, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e3d27bf2-6f92-4116-84bd-65669f66480b', 'Fixed Interest', 443, 48, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4b046888-143c-45d5-8508-5ce1ca61349d', 'Indexed Stable', 15425, 53, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1869c458-03bd-42ae-98fd-9f20c793a8ab', 'Cash', 184, 22, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9011f674-4753-4056-bcaf-3559a21e3890', 'Cash and Term Deposits', 613, 71, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('912888cf-4694-4184-9bc8-ac03a3d0f768', 'Glidepath: Cruising', 648, 76, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('adce3df4-e223-45ad-bf85-72a960802b17', 'Overseas Shares', 188, 22, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('24c6d7f1-1741-42b0-91e3-f81513ecbd13', 'Conservative-Balanced', 13858, 78, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0ea2fdeb-5bab-422b-9c7f-9ae0b2d91c25', 'Australian Shares', 293, 34, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('80696402-6c06-41a9-9341-bc1457867b34', 'Aspire 1', 656, 78, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('605dd5ff-0c3b-4d8a-83ed-bf38e80e27dc', 'Cash', 749, 76, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0b374198-1209-4bff-a652-912aee407808', 'Overseas shares', 507, 56, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d7057499-a583-4154-9430-b9abb12e243b', 'Cash', 639, 74, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('868af444-b3b7-41ec-adfe-518fa7576384', 'Property', 9338, 28, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7ac06092-e05f-4956-91ae-e66a1451ae94', 'Cash', 319, 38, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b1457370-744a-4927-95ca-11e0130f9159', 'Ethical Diversified', 321, 38, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('21b36113-8c83-43e5-99d9-d5715768e81f', 'Indexed Diversified', 9516, 27, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('be52d885-8e60-4857-b2c8-287ce2120d33', 'Cash', 435, 49, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6456aec7-d3df-443f-9059-0bb2b20c7998', 'International Shares', 432, 49, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('60d2d082-57bf-4075-9140-4040463ef06b', 'High Growth', 29, 12, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a6323c06-aa7c-4351-9a56-3f3f0728dd69', 'Balanced', 325, 38, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e6b97131-4883-45f1-a973-1d6af43d9f15', 'Australian Shares', 635, 73, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b8d85519-cc50-48f7-92ec-261f5f8cc9e0', 'Capital Stable', 179, 22, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('67f54b42-4963-4c1d-9b45-e7a992b7afed', 'Appreciator', 10552, 59, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('8962d027-ba9c-4575-86c1-36707355b7d7', 'Australian Shares – Indexed', 9150, 53, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('647bf727-4b2c-4f89-a2c3-48c4973936cc', 'Indexed Diversified', 9588, 64, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('eca82711-e205-43f9-ae07-9fdffe7f6572', 'Cash', 312, 36, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('88d22627-e959-4143-9c09-2678a1247a82', 'Cash', 600, 70, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('672d39d4-b3e3-4383-b621-32d804bb341b', 'Listed Property Index', 746, 76, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3eddf7a8-d3d2-4e17-a33e-4edc850c3a35', 'MySuper', 57, 13, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2166786b-0589-4992-aee4-74096a13a0aa', 'MySuper', 629, 74, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b2c2199f-d342-424e-9ac2-eb2fcbcbecca', 'MyPension Balanced', 998, 70, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('de8ffb26-ea71-4e70-aee2-8a0dad879762', 'Growth Plus', 9334, 28, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1e56f215-12d6-4113-8702-7326120143d7', 'Conservative Balanced', 407, 47, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('81b3d666-3a44-42c0-bc18-23c1e3727fd5', 'Cautious', 68, 14, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('15523753-e1a4-4b8f-a24e-bac470f2b6f4', 'Sustainable Balanced', 181, 22, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6064b6c1-66e0-4d97-a032-5c8a08af12e0', 'Australian Shares', 9590, 26, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a86eecc7-9896-4525-9d02-36472f0dac68', 'Conservative', 215, 26, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('67621dff-6043-4131-9809-4887459af4ef', 'Property', 637, 74, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('bb08fb73-2b3a-4300-a6dd-06b39f64aceb', 'Cash', 588, 70, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5b06cdfc-4eb4-469c-84b4-c3e1ca9e9562', 'Managed Cash', 515, 59, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ace830e4-c8c6-4024-98d7-cc53be06bf56', 'Balanced Growth', 329, 38, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1e0aa57c-410c-4bb3-a7b1-97f54a9b6d1b', 'Moderate', 370, 43, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('75bbd9d0-463f-4472-9c37-c2b38aed6814', 'Capital Stable', 317, 37, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('63b15687-83ef-4bbb-9c53-646eb6d9005b', 'Conservative', 316, 37, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('380339ee-c316-4f36-8408-d2b6218e0f68', 'International Shares TTR', 450, 51, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('df3f53ac-3c0e-4ad1-8546-fd3153d15387', 'Growth', 518, 60, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5525e5b2-dd6b-4f4f-8dfd-8184d647b464', 'Conservative balanced', 501, 56, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('cc96d7e8-8da1-42fa-a607-e0066815cf08', 'Conservative Balanced', 9981, 61, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('222bf955-b75b-4422-8baa-7aadd0e3100c', 'Accumulator', 10551, 59, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9403dfae-3353-41a2-8321-3db64b35adf8', 'Australian Shares', 9337, 28, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4f674387-f49d-4f5c-a8bc-52d5806bd542', 'Aspire 2', 657, 78, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1b84da3f-db36-4027-bdff-bd7fcd35dc55', 'Australian shares - Indexed', 36, 12, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('92323682-693a-4fa4-9812-5f80ce73a187', 'High Growth', 12148, 52, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('749df249-3561-4633-a312-49c03c3e945b', 'Cash', 328, 38, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c79a0bb1-ce56-40ab-83ad-e6ba8b127a40', 'Australian Shares', 464, 53, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('72e85b25-9ef1-4272-ac46-90bb2abc3056', 'Appreciator', 10552, 57, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6457dd9e-e067-487b-b68d-5d723479d780', 'Balanced', 572, 66, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('25ad8d3e-bb46-4a18-bd66-9c3385f81f46', 'Managed Cash', 515, 57, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b429c266-9273-4e76-b0fd-389ff281b3fe', 'Sustainable Responsible Investments', 309, 36, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('722c7613-2f73-40ab-9ef5-c5da20a485dc', 'Socially Responsible Investment (Sri) – High Growth', 12152, 53, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e7f619ea-4ce4-49bc-8c27-712dc8ecefd0', 'Alternatives', 631, 74, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('aeec14fa-4d23-498c-9b28-d7e61fe4391a', 'Balanced', 313, 37, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('cac87270-cb3a-43d2-942b-2a9f9390431a', 'Indexed Balanced', 9555, 60, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('93afa007-2e77-4d6c-ba0a-7f03c88e0de2', 'Balanced', 603, 71, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('fc202981-bc7d-4bb9-84ee-df26f3a9b9cb', 'Australian Shares', 307, 36, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('64cbe413-1c3f-42b9-a612-bfe622c0e04d', 'Overseas Shares', 308, 36, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('68854228-5663-4d90-9254-9d2ef9d64bf8', 'Overseas Shares', 9589, 28, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('140c6f07-f7d8-4e0b-91d8-2e846aff5ebc', 'Growth plan', 427, 49, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('cf76bbe6-7a5d-4439-86e8-fd4d96aac272', 'Growth', 243, 28, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0db0e1de-197d-4fa7-97ab-e197cef1fbcc', 'Shares Only', 314, 37, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('08042d45-77e0-4a6d-b18f-5df3c698f52f', 'Property', 433, 49, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e8b4d2a8-b712-4898-9044-88906f2c35ef', 'Cash', 444, 51, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('12577e8e-9d02-4bf0-8da2-2ea2c2fc07b9', 'Defined Benefit', 15038, 76, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('09bfad6a-bab0-47ee-a72d-41b44bf5133a', 'High Growth', 212, 28, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4fd69596-c022-4bc2-977e-5994fe17583e', 'Defensive', 604, 71, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('33eb449d-be81-4875-8415-89a1eb116085', 'Balanced', 92, 17, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2770a0f1-30db-4542-939d-aa24babe0edf', 'Property', 592, 70, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c522d880-7da6-4b51-963e-9bb41ff29140', 'Shares Plus', 404, 46, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d99003ed-1865-48e8-b054-5e5eda09cfc5', 'Conservative', 514, 57, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d70a0ec9-1a3a-4181-9875-596c48352703', 'Conservative', 514, 59, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d5684409-ce56-48ff-8192-e9faadfd124a', 'Socially Responsible Investment (Sri) – Balanced', 8792, 52, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('fc9d12da-72d9-47e8-a385-2ce9bb6fad50', 'Secure', 522, 60, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('96bbb387-36a5-4b2e-97bb-ae110e6da331', 'Conservative Balanced', 407, 46, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ddde2aab-7603-409a-9956-3e721e1d5203', 'MySuper', 516, 60, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1b5a7170-8c71-422c-ae00-3a4c68c7050a', 'Bonds Index', 748, 76, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d4f51c74-ff4e-40e7-9097-8c968e5e1cb9', 'Conservative', 455, 52, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5a8777cc-dced-4a60-932e-b87309ef51a1', 'Australia Post Defined Benefit', 15044, 76, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('40f8c889-7bcc-451d-beb4-bc344fc29605', 'Property', 525, 60, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('fbdbb910-3105-45e4-8f6f-cb59121400ca', 'Balanced', 165, 22, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6061d00a-bc2d-4260-990b-faf4df46a30e', 'Property', 637, 73, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3bd15e9e-2c3f-44c7-93cd-479eea6d8b98', 'MySuper', 287, 34, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('bc471f27-9286-4948-9140-9e03bec1d1b9', 'High growth', 505, 55, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('61cdd78d-092f-482a-9837-fe48b5f7b434', 'Energy Super Defined Benefit', 16345, 61, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ba1f361b-4d6d-4efa-8cd3-a44514e6099f', 'Diversified Fixed Interest', 9332, 27, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('38daa8b3-5eec-46b9-b4f0-33536bbbf24b', 'Growth', 183, 22, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2954c606-f63f-4f9b-a907-eb26dc4b0592', 'Balanced index', 502, 56, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('57c69fea-2489-4b62-aeb3-ddaf75f8e191', 'City Defined Benefits account', 16346, 61, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c9dedd9b-0a69-4227-812b-4201b4c8d69b', 'Australian Shares', 198, 23, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0f230d1c-2227-4c7e-a6b3-1618860ac0b8', 'Glidepath: Take-Off', 646, 76, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('faed85f8-85f0-430e-8d76-39bed5973e84', 'Cash', 666, 78, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7c11aa0f-0839-4238-a6f2-80b19b15406c', 'International Shares', 487, 54, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5a28c73f-5456-4ac1-8519-efcedf2eeb90', 'Sustainable Balanced', 146, 21, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0afff918-c17e-43e6-ad25-66c0c3adab7d', 'High Growth', 602, 71, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3c41fee1-58e6-4c67-9742-81a626e2ef70', 'High growth', 505, 56, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e1ab7e93-4aa9-4493-93a1-962b39b5d96d', 'Balanced', 512, 58, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('274dc95d-6c53-4497-9bb2-276137e38393', 'Cash TTR', 453, 51, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('189e73d4-9c2f-45e4-b60d-d9a1d7b5fe19', 'Growth', 213, 64, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('bd30dc88-0a52-4447-b73c-9a4eab1a9f27', 'Property', 9331, 27, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2bb7107e-39a5-447c-9569-045febdaa3bc', 'My GESB Super plan', 426, 50, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('05544925-112d-48d3-928e-c5ffdd52cc5b', 'Conservative', 480, 54, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4a8293a9-9d73-407e-9cfe-a6738c24f7e6', 'Balanced Growth', 304, 36, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c57b81d5-c334-4a79-8831-c91f45e0b7c3', 'Future Focus', 294, 34, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('48db644d-797e-45d8-aaab-0ca34a6e597a', 'Defensive', 327, 38, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9370a245-8a15-42c3-a864-bf51831aff78', 'Cash plan', 430, 49, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('19a46ddf-89c4-4037-92e7-c0481c1f3d30', 'Australian Shares TTR', 449, 51, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2b01b482-0e3a-435b-9df7-ff8b39c05387', 'Cash', 588, 69, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9c7c7464-1154-4fb5-b163-c308324da5a0', 'International Shares', 98, 17, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('32ea06f8-cfad-4c9b-971c-79c50d45a522', 'Overseas Shares', 295, 34, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2a2256e9-6e02-4da5-9b07-db1027fb62d4', 'Australian Listed Property', 484, 54, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6ecb922a-660b-4d5f-b528-d275ac1163d6', 'Appreciator', 10552, 58, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e3aa829f-fbc5-4bea-b72b-7b869bf5009f', 'Conservative', 632, 74, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('56642b04-a2a7-4780-9cbc-5a054783baf9', 'Cash', 217, 27, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('25509c9f-e3fd-473d-9f97-4a49b7f48f72', 'Managed Growth', 630, 74, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('60f81a66-0710-4f52-8ebf-fedcf4d9aeac', 'International Shares – Indexed', 465, 53, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('8f1df050-1200-4294-90f1-a55a5def6ec0', 'Diversified Fixed Interest', 122, 18, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1d23075e-46cb-4fb3-a0e4-21b312eff553', 'Conservative Balanced', 513, 57, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5a00e004-99be-43d0-a2f8-50015f19a841', 'Defensive', 318, 37, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('351ec34a-ce78-4474-89c1-d6f590acc6b9', 'Balanced', 512, 57, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('04ef34b7-1b00-4d05-baeb-656b6d08569a', 'Australian Shares - Index', 741, 76, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('836a1dd9-1a3d-4900-89e4-9c393c512c39', 'Property', 996, 13, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1e271920-fce4-4b2d-9a0c-19f4b5ea38a8', 'Socially Responsible Investment (Sri) – Balanced', 8792, 53, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ccd45109-f1a9-4223-a46a-cd5777a62355', 'Growth', 478, 54, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('36352b5d-85e6-4c4a-8537-07a2b6e2ed97', 'Income Focused', 633, 74, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('cc665f82-4407-4d71-84cf-caf29e1ba6d8', 'Conservative', 215, 64, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d971de82-67be-4ca0-9057-87722086681e', 'Conservative', 306, 36, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6d9916ed-c7f6-4a76-9371-d518a86dfbf4', 'Growth', 58, 13, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('97d8c92e-80ad-442d-b155-391238711706', 'Growth', 518, 61, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2a206c80-0d0e-4036-9f79-f87e13bad5a2', 'Australian Fixed Interest', 482, 54, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('36ad17d5-5075-4f4e-8e2d-5f91d4c068be', 'Australian Shares', 97, 17, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e6d0affa-738e-46eb-af70-f936cfec2f55', 'Indexed Stable', 15425, 52, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('674f041c-1afe-4e48-9864-190fdd432dd9', 'Regional Defined Benefits Fund', 16347, 61, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('213224cf-ae53-4352-883f-c19df684c06e', 'Stable', 1000, 70, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('107fa2d2-f7cf-41a2-a346-8ae073eb315d', 'Stable', 589, 69, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e2d79e8f-02ba-4ec1-89cd-d4309bceba78', 'Cash', 235, 28, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('37988823-5534-4773-8481-55fc9cc2bfaf', 'International Shares', 16897, 13, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ccfd9d9e-7bff-41ac-82b5-46361f1019d5', 'Australian Shares', 419, 50, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d7323bf5-cf5b-4929-aa54-01bfd5a680d7', 'Australian Shares', 9330, 27, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0b852cd4-2d21-4b8f-8f17-6894decffae2', 'Cash', 570, 66, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6f366bb0-d347-4830-8cdf-71c30b9db9c6', 'Bonds - Indexed', 9149, 53, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c646f2b4-028a-4e28-8037-24ffba162548', 'Conservative', 231, 27, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2dd42ce6-c4f2-4713-b52c-c654b53d72af', 'Growth', 315, 38, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f1933519-07c9-4396-9791-35d46263901c', 'MySuper Balanced', 642, 75, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('05cf75f8-57e8-421c-b840-fcb4944293f8', 'Growth plan', 414, 50, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e634e5f7-6a88-412a-95b0-08c32cf4416c', 'Balanced Socially responsible', 504, 56, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('818ced23-30f7-48b9-a6ce-854a3fc1dbc8', 'Balanced', 617, 72, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c778142a-2560-4514-8762-f63fabd21923', 'International Shares', 120, 18, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('bc8f1dfb-983c-4a24-8bad-b7d19537ad9a', 'Cash and Term Deposits', 628, 72, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3cfd9291-cb05-4c3b-846b-7eb402061ce0', 'Direct Property', 151, 21, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('befc0543-2ae5-483b-9455-f426be320ddc', 'Australian Shares', 440, 51, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b21d7a0b-4661-4c0f-9f9e-9faa375e528d', 'Diversified', 601, 71, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('573503e0-2f2f-4d89-bd75-1b7d3b1e1b6f', 'NESS MySuper', 590, 70, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f347da91-5669-4fa1-8964-e464e6b37e07', 'Growth Plus', 302, 36, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9f108830-d297-48fe-b26f-6e4611161294', 'Indexed Diversified', 9588, 26, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0024496e-e271-4eea-935c-89e267b3eeed', 'Growth', 213, 28, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('507b378d-d45e-4424-8fed-ff36e6ac11f7', 'Growth', 291, 34, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('40770508-38f8-4652-a186-38a78c481d74', 'Alternative Growth', 182, 22, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('213dcf86-a376-4c47-8fc0-2ebb44e8cef8', 'High Growth', 212, 26, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('aee12819-cfb9-4d33-9dcf-821455cd1ca7', 'High Growth', 509, 58, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('92c3bf64-98cd-43b7-816d-2afd414f9839', 'Growth', 213, 26, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('75574d89-06c3-45b1-8502-644effc95b04', 'Cash plan', 439, 48, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('069ae820-29c4-42d9-8476-9d1061ffc575', 'Socially Aware', 112, 18, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d88d52be-d482-4820-a19b-f5bfcbf1926f', 'Cash', 423, 50, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4d706e75-a459-4391-9c70-d7b7ac1d992e', 'Socially Responsible Investment (Sri) – Defensive', 12153, 53, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('13774772-66c8-459e-a477-7929ebd4860e', 'Cash', 406, 46, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('659b4715-7471-4dd4-9d49-b43356700307', 'International Shares – Indexed', 465, 52, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('95efaebf-ab8c-4b41-aa01-ebe54623ac89', 'Cash', 488, 56, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a56dcebe-f4f1-4549-af37-3082dda61f20', 'Balanced Index', 13862, 78, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('fb6a81db-4829-4a2a-9867-b51de73ec29e', 'High Growth', 616, 72, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d31f6c55-79a0-4d84-ba7d-884d39ec1cf8', 'Cash', 101, 17, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a09e55a1-ac64-427b-b172-80f2360d0c7f', 'Overseas Shares', 1002, 70, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('14b2e075-c116-417a-ba31-2351b49d7868', 'High Growth', 234, 27, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5f2a41a2-7d6a-4711-a426-ab46fbe0c837', 'Balanced Growth', 191, 23, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c6cf1d34-8a11-4f30-9e22-b862f4b8d439', 'Moderate', 479, 54, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2b52dd9b-83dd-421f-88eb-48c6db82d8bd', 'Balanced', 519, 61, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('26aa0e3f-156a-4e5e-9747-d08db6701966', 'Overseas Shares', 153, 21, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('015976f5-1be9-4936-84e9-9d1d73890586', 'Property', 626, 72, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f101fe1b-cdef-4f8c-8bbb-e67497d3999a', 'Growth', 324, 38, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0d835d0a-2440-433d-a9bd-27abf76e5bbe', 'Ethical Diversified', 330, 38, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2e7e53e2-5a70-432b-9684-0949c2dbbae2', 'Cash', 488, 55, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('13308c1d-1912-41a2-86c8-7ec00aa01266', 'High Growth', 13857, 78, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9ffa2e2b-188c-40e4-b73a-7347874dae71', 'Cash plan TTR', 448, 51, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c1414007-1ddd-432e-8a2a-687c4df8d6c4', 'Cash', 202, 23, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('37f4764c-a968-47c6-94cb-ab99006341d6', 'Growth Plus', 189, 23, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('95a909ce-e026-4c75-b66e-9ab1c5c36801', 'International Shares', 636, 74, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('79df69c2-6d7e-459b-822d-88b20ac43bae', 'Alternatives', 631, 73, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('444666ff-9a82-4d1a-ab61-a44385583533', 'Growth Plus', 292, 34, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('33be171e-3a9a-4c37-884c-828e0901c41e', 'Conservative Growth', 214, 64, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0fef3c2e-9701-4a2c-99a1-25a0669f5c55', 'Cash', 653, 76, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('77bc92c1-6331-42ee-9dde-8416cf39446d', 'Balanced', 193, 23, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('cb6ad299-0f12-454c-8883-31fa6e088107', 'Accelerator', 10550, 57, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('12b826ce-bd25-4b83-bc5a-3f09e4f9b01c', 'MySuper', 196, 23, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c5ad4ac3-48e8-4445-9bd1-66b49efc8f42', 'Cash', 69, 14, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5fcdd5e1-307d-4a1f-9911-3ea198172aca', 'Growth', 373, 43, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('20ab3d2e-ce0e-4816-814a-198a77c0f031', 'Cash', 123, 18, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('40063c25-f8bc-454d-b4e3-1d2cdce6da86', 'Future Focus', 195, 23, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3e94260e-357c-4eb8-836f-6e0db4965248', 'Secure', 522, 61, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('29a4b328-1474-4745-aea0-b03427339ec5', 'Cash', 639, 73, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('079fb004-f57f-41b7-b5ed-bc2a2c2018ab', 'Growth', 408, 47, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('88458d1b-a683-4bea-9a88-22c9b29becf3', 'Socially Responsible Investment (Sri) – Defensive', 12153, 52, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0e9dad54-93f6-430d-bfd0-5ba7630a1e62', 'High Growth', 477, 54, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ff5fcfab-d32a-46d1-97aa-1e4f7bb8112c', 'Indexed Conservative', 15424, 52, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a0b00635-82ca-4bac-af1e-46e251dd2def', 'Conservative Balanced', 180, 22, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('68e5a07e-e4f8-460a-bece-3992bda4d80c', 'Diversified Fixed Interest', 9339, 28, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d3774449-9f1a-4870-8633-4de2a5bf8e08', 'High Growth', 509, 57, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('88447800-e293-4c17-a744-9e3250e32cbe', 'Income Focused', 571, 66, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('78fbbd0f-cf47-44fc-bc2a-ddb23f29ad26', 'International Fixed Interest (Hedged)', 483, 54, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('83aabbe7-0122-479e-a0c3-eb23aeb817f1', 'Balanced Growth', 67, 14, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('751262ba-1452-4679-9fd6-cca220b3b28e', 'Indexed Growth', 14908, 53, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('40c185d8-f9a8-42b0-bb7b-ca00846baeb3', 'International Shares', 420, 50, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b9123667-5ab3-40ba-a2e9-8a4f8cac8f4a', 'Growth', 148, 21, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('18b0a158-7105-41f7-8d0b-ffbe4d32b9ef', 'Glidepath: Altitude', 647, 76, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ada8ad66-3e01-4928-853a-a6fc6eefc089', 'High Growth', 91, 18, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b2eef553-5df4-40f7-8616-36f2eec67184', 'Cash', 527, 60, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('85c09d01-7df5-47f6-bedf-fc9d4d56ee9d', 'Australian Shares', 608, 71, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7661539a-141f-4d5a-ae6e-c88e07c51dbd', 'Growth', 459, 52, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('30cbb8f6-71a6-4c1e-a02e-e67b4b551258', 'City Defined Benefits account', 16346, 60, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('8b03b086-a582-4d60-8085-09a423d73282', 'Australian Shares', 16896, 13, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('896d2547-f0d9-40eb-b690-810628404bd8', 'Socially Responsible Investment (Sri) – High Growth', 12152, 52, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('54934efc-d2f6-4340-b115-fb1aca88b89c', 'NESS MySuper', 590, 69, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('117dc956-6ca8-4421-8104-661007368b33', 'Diversified Fixed Interest', 100, 17, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('af176363-4dca-4dad-92a7-83977aeae45b', 'Conservative', 738, 76, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5fd3501b-4e79-41ba-a4e8-8a614ec8d0b6', 'Fixed Interest', 638, 74, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('cb556916-88b0-4b6d-939a-0e794e28acb7', 'Australian Shares', 119, 18, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('36877836-79ac-49c5-9967-dbd2439d5553', 'Fixed Interest', 443, 51, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('8a37e6e9-3e88-44ee-884c-45683a755171', 'International Shares', 636, 73, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c35771d1-804e-4a2f-9130-30710ab3a67a', 'Stable', 114, 18, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('06ecf647-e4b1-4f86-9f58-372f9fec6c1f', 'Direct Property', 186, 22, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3653bb4a-1a73-437d-adbb-cc8f8508671e', 'Conservative plan', 417, 50, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f083c527-0a86-4047-913e-23becc288408', 'Aggressive', 644, 76, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('686cffe4-2582-4269-bc9f-c856ca709109', 'Income Focused', 633, 73, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('cef596b4-7243-4fb9-a654-806a13125e78', 'MySuper balanced', 503, 55, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e68ac97f-bc12-4ce1-a116-d8db1073fe4b', 'Aggressive', 573, 66, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('8cc74027-6f3a-4669-953a-38d2d3673ea8', 'Property', 442, 48, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ca555164-2e4d-4f88-9c7b-93273d2833cb', 'Australian Shares', 9590, 64, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3c5bf05b-abd0-47e2-82ef-47679e8840b9', 'Capital Stable', 143, 21, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ad8c0b6e-2859-43d3-90ed-8d0b331e61d5', 'Australian Shares', 485, 54, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ed238c89-c102-4966-b8f0-e8e99182d8cc', 'Property', 9591, 28, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7d7f3c70-2691-447a-a318-b1572d8eeb8d', 'International Shares', 523, 60, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('02f4de7a-500f-421c-a308-3a909f0cbb96', 'Balanced', 519, 60, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3e270651-3dea-4a2a-929b-bb82fc1250a5', 'Balanced - Index', 734, 76, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1c9f91ee-50bc-4459-a49a-931476346829', 'Australian Shares', 593, 70, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('83bfb36c-e077-4ee5-b7f2-d3f484a51abd', 'Conservative Balanced', 144, 21, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7218e894-2af4-4556-a984-e5351c37ea88', 'Growth plan', 436, 48, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0909de5c-1c70-4663-a4c5-02e89d523a84', 'Conservative', 490, 55, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('acb590e8-a346-4049-9dec-25dc3a4b5568', 'Cash plan', 418, 50, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('88c6ff72-fa39-4ecf-a7e4-59a822182caa', 'Indexed Balanced', 457, 53, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5669d53b-a7ad-46de-92c8-e243a2c5b070', 'Managed Cash', 515, 58, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('28331972-0cb5-4bb8-b9a5-e6683033d260', 'International Shares', 523, 61, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('466ecb03-1e89-464e-bdfb-323f2a85d255', 'Balanced', 145, 21, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('88a2e316-c7d2-4d00-aaee-69038f0135b4', 'Indexed Diversified', 9588, 28, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('fd75b0d3-9cbf-4f33-bccc-87505bb0a3f6', 'Stable', 454, 53, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('25d12d09-2282-456d-a3dd-f7564329b8d1', 'Fixed Interest', 638, 73, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7919bf09-2e84-463d-906e-1f46ef36ea9b', 'High Growth', 109, 17, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c83040a1-d87c-4ca4-8b50-1a575aeb46e5', 'Cash', 371, 43, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('547422fa-4fc8-4d6f-805f-061ab990f958', 'Capital Stable', 317, 38, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('48d43a16-cee1-4199-b2f3-6393640126a2', 'Property', 9591, 26, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d4d6e286-286f-4c64-b7d8-9a38a8979b5d', 'Conservative', 652, 76, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('55d93cf6-0929-4f6d-92ac-617d2cc659fb', 'Energy Super Defined Benefit', 16345, 60, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('98763132-d21e-4ecd-8c8e-30ecd45c53c9', 'Focus 3', 654, 78, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3286434f-3acb-433f-b065-b66d6fc53a3d', 'Secure', 55, 13, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2372d247-095e-46b3-a37c-7df259a499e4', 'Australian Shares', 1001, 70, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c807d18b-82ee-4fdf-9884-29209def13c0', 'Overseas Shares', 9517, 27, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a3eaf44a-35f9-48cc-830b-bdea82348aac', 'Accelerator', 10550, 58, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f4a1386b-c22a-4fb2-a305-97474df3a2f8', 'Defined Benefit', 15043, 66, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('cbb6242a-f369-4d2c-a728-7ea290d35e4e', 'Growth', 190, 23, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e57cff7f-fdc7-4e2c-ab34-67fa64f1f729', 'Accelerator', 10550, 59, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('64158833-40fa-4bd9-823b-c8529ff76601', 'Defensive', 12149, 53, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('35cda683-abc4-47e1-b7aa-7baaf6d68e8e', 'Accumulator', 10551, 58, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('385034e2-e14d-4b03-827a-3a852fce83e6', 'Cash', 31, 12, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d08a8f32-c58c-463b-a446-a560a64d6a84', 'Sustainable Balanced Plan', 13577, 48, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('30bf571f-ae48-4f59-a56a-aaa5db66f59f', 'Cash plan', 439, 51, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1890a494-292b-4b55-8bb9-5c7698567b6d', 'Defensive', 618, 72, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('746075cb-c565-4436-8e76-4ab4a9bb70bc', 'Balanced index', 502, 55, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0b5c358f-089d-4a32-8737-20ba0b09d083', 'Sustainable Balanced Plan', 13577, 51, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5ba27399-8abb-4486-8417-cd612b78ade0', 'Property', 9591, 64, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d6e63e84-9d0f-403c-ac90-c20bf7062fce', 'Growth - Indexed', 27, 12, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e38e0d83-7986-41d3-8b26-76b06c9ecdbe', 'Shares Plus', 413, 47, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('8d4d6634-da7d-457f-8b3c-f615a6c09ad0', 'Indexed Balanced', 9555, 61, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('14429ec0-e19f-4182-9136-215c949c790e', 'Infrastructure', 610, 71, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2dec67a4-8c59-4b2f-a6cc-e70ca8431eff', 'Cash', 460, 52, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9559b885-ed8a-49fc-b6b9-b51a43c29279', 'Growth Plus', 9587, 26, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('690aff9e-c11e-4566-a1e0-77c41400950f', 'Conservative', 316, 38, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('fcfde874-3717-4e84-8dfd-84df662c6385', 'Balanced plan', 437, 51, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0be68397-6156-47e7-849a-6af3de946c1e', 'Focus 1', 658, 78, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c0b68e90-7d79-41e1-ab0f-ad078046e9d0', 'Growth', 412, 47, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6bf90b8c-9985-467b-b2bd-f3b5e9acfdc7', 'Australian Shares', 593, 69, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e073dfcb-6cba-4153-b513-f3d3d8536aea', 'Diversified Fixed Interest', 9592, 28, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e73a0fed-5d10-4a2b-a0ad-f4c01cfc471b', 'International Shares', 441, 48, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6fcb45d6-bb0f-41df-8df3-13e085d5ceb8', 'Indexed Diversified', 192, 23, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f7481938-9408-4b55-a8ff-9a0709743ef4', 'Shares Only', 314, 38, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2a6405be-e7fe-4ac9-bd7e-f1a85017e02b', 'Growth plan TTR', 445, 51, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('97a1cf1d-ad14-43ee-b56e-f6f5b512aa5e', 'Cash Savings', 216, 26, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('08f07aa9-51bc-477f-8026-86d9f8685155', 'Defined Benefit Strategy', 510, 57, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7cda89c1-77c8-4cb1-a1db-f082c3dc3dca', 'Property', 592, 69, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('425f7bbb-615f-411c-b3f5-656ee3186a2d', 'Growth', 408, 46, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('59ecb1e3-8a72-4d3e-9870-02f68f2f7c14', 'High Growth', 591, 70, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('15c6f864-0b30-4e37-8723-2326a8601a3f', 'Diversified Fixed Interest', 9592, 64, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('afb05b48-6875-4973-ba45-1c359b356f14', 'Stable', 589, 70, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('61bcffa5-e084-45d5-bf40-d1cb3e614906', 'Income Focused', 641, 75, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('8f64a393-44ff-4c64-8853-0056ccd6064b', 'Australian Shares', 375, 43, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0a00c740-6249-4186-ad2d-cfc7043e0eef', 'Property', 442, 51, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('bf2fb9c3-820c-433e-a6b6-93d15f68573a', 'International Shares', 609, 71, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1fa1fe33-c6c3-439a-80f9-7f5f76c9e64e', 'Australian Shares', 152, 21, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('876a523a-5134-4814-bbf1-0a953614f001', 'Conservative', 326, 38, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a9b62390-f17a-48c2-b2ce-ba3e5c85f283', 'Growth', 496, 55, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('79c9a415-331d-4b8e-b2e6-63c23deeb80a', 'Diversified Fixed Interest', 9592, 26, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6520a87b-92d1-4b88-b305-5680b10a0be8', 'Bonds+', 461, 53, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('046d3126-cd01-4edb-8ec9-bfc5c1cfd647', 'Balanced Growth', 320, 38, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('bf12f8ec-e787-4631-ad38-2c87e7805768', 'Enhanced Cash', 500, 55, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0eedd0ed-399e-4ce0-b62d-ca389181974e', 'Australian Shares', 1040, 447, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('eba88279-68bb-46fe-afae-6903dd2b5357', 'Property', 791, 397, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('fd53976f-4b41-460e-a907-8089b4e22a6c', 'Cash', 1038, 447, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('14d66520-8b85-40e4-b21a-926a42edc401', 'Capital Defensive', 757, 89, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('53346fa8-f698-4ae8-95dd-c0be6e2c6570', 'Moderate', 787, 93, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5d4ff783-88f4-422a-ad07-966670bd2fb3', 'Australian Dividend Income', 831, 98, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('017cd3e2-8993-4ce3-a006-b06f9a7c5980', 'International Shares', 789, 94, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('678a6422-c55d-4fda-ad91-e67bfe585798', 'Moderate', 787, 397, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ce6e7580-3621-41e6-99d3-0d529a985807', 'Cash', 680, 389, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('10c99f25-1487-4c11-865f-5728fb8cc2be', 'Diversified Bonds', 866, 102, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('db2a99dc-7917-40f4-a64d-440672a16532', 'Mysuper Growth', 793, 94, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f892991d-a2de-4310-b950-10829e77f430', 'Australian Equities', 864, 102, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4210267d-5fdc-415e-9257-01b71c231d01', 'International Shares', 1041, 447, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0d1a0996-86cb-4127-bbff-07229733d3d2', 'MySuper Moderate', 14009, 397, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0bc40906-31c9-4229-81be-737bc243361d', 'Mysuper Conservative', 795, 93, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('54374727-151c-464d-9195-ddfc7210f136', 'Mysuper Growth', 793, 397, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5db206f9-282c-47fd-afed-d22a58e46333', 'Conservative Balanced', 803, 97, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('61b7d54b-8545-4f40-abd5-a5d0ebded228', 'High Growth', 682, 390, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('06133bdb-8d92-4c35-8b45-0709e43e7611', 'Cash', 848, 101, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('cae395d4-faf3-4b7b-95ff-edc81db9861e', 'Property', 791, 93, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1cb936ea-c09a-4cda-bcdd-7bda4646f068', 'Conservative', 861, 103, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('8e4880bf-b9fa-47e9-a50f-8783d1c093cc', 'Global Companies In Asia', 816, 97, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('740e1d10-9a9e-4ba3-9d3b-57ee140f2d85', 'International Shares', 789, 93, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3ada8748-7f27-4e2a-8a62-c0299d8b5535', 'Global Companies In Asia', 832, 98, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a172dd36-4725-4170-89f2-53ff1c98f0b2', 'International Shares', 789, 397, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b7fd95ed-6b7a-4493-936e-d9fec2bbfec8', 'Diversified Bonds and Credit', 792, 94, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('51dfb9e8-7c74-455a-b3b6-0ff81e317138', 'Indexed Defensive', 8967, 122, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6940818d-3da8-4a7f-9478-5430265c2028', 'Defined Benefit', 15037, 94, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d8239709-217c-477a-8af3-6a689ef022f1', 'Growth', 806, 97, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4ea7809d-4608-430c-a700-28512e703c6b', 'Bonds', 956, 123, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3851a610-4a41-4424-bb7e-1af151db4c3e', 'Born 1949-1953', 846, 101, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1c05a6f8-d39e-4c72-b390-5fd9024986b9', 'Sustainable Balanced', 821, 98, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c496b34a-8a88-40e6-aa78-559518428433', 'Secure', 9154, 123, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3f4dd9a4-f32c-48f1-bf04-81d17a266cbe', 'Diversified Bonds and Credit', 792, 397, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('229e6e1b-b8dd-47a3-893f-c5b74aeed056', 'Balanced Growth', 858, 102, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('918cc098-3927-401c-b48c-b37e3ff32e9a', 'GrowthX', 967, 126, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c236834f-a242-463a-a1fd-4fa309720c16', 'Cash', 957, 123, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0384f020-cd25-4efd-9cb2-3e5f6f9bd6ee', 'Spaceship Moderate Option', 16321, 126, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f84532f7-a52e-419a-945b-1e3526097c6c', 'Shielded', 14268, 148, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('49bf2c1f-baa1-4392-b8b0-b1a72b7d30bf', 'Global Environmental Opportunities', 830, 98, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3400f7d3-6831-4459-9bb4-58bf97ebd06c', 'Moderate', 689, 81, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('85a1850e-440f-4802-877a-faf4d93a81a6', 'Cash', 14260, 148, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3417dc6e-9ac8-46b4-9194-4b90e94a472a', 'Conservative Balanced', 819, 98, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('cb38ffd9-dabc-4cc2-9d81-193567db8aea', 'Global Environmental Opportunities', 814, 97, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('296071bf-b930-4dc6-adb3-b76c6b5816cc', 'Listed Property', 14265, 148, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f3836cb1-e088-4e51-b2d6-3071c8970b4e', 'Mysuper Balanced', 794, 397, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9e66d567-1c56-4a5f-8f0e-5346660fbf64', 'Growth', 670, 79, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5b183334-07a3-4211-9ad1-67e89adec077', 'Cash', 785, 397, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('338741b1-dc66-4bbd-ad45-ecb8afe54e80', 'Australian shares - Indexed', 36, 381, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2766ce53-0f98-4905-8ff8-266db245d74f', 'Property', 791, 94, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('343d8fc2-4395-4401-9782-4e6839877dab', 'High Growth', 682, 81, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4eb296ba-4a0d-46d9-84e8-5cd9410a62e6', 'Unlisted Assets', 13867, 380, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('08ed4ea0-f9c1-4d24-b257-2ef89a1bd6e9', 'Specialised Australian Share', 14269, 148, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('76fc3249-3d48-4414-b250-f83eb96120ec', 'Bonds', 949, 122, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e5a54b84-9c62-42d3-8b0d-6706835741e6', 'Defensive', 691, 389, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('67ec88e0-2b6d-4e77-9eda-98518f674f0e', 'Defensive', 691, 81, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('379b6180-e6ec-466f-8d2e-6de45e9816f9', 'Australian Bond', 825, 98, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ad849c93-c818-4d88-a9f1-bf881c78ffa8', 'Moderate', 755, 89, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('39e84c2b-3a4b-40c2-8b46-9c62f9515a75', 'High Growth', 942, 122, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b84e0652-959e-4d2e-8091-3c19552fd781', 'Born 1954-1958', 845, 101, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d900b078-0061-4242-b981-7ca0f257ed6b', 'Conservative', 861, 102, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5cf3c25a-641d-4ce7-ada0-849281d993dc', 'Cash', 867, 103, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9abd06e3-fc92-4f4e-8a2f-9143129650fb', 'Growth', 684, 389, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('651c588e-34bb-4927-a81b-23a43886436d', 'Diversified Bonds', 866, 103, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('adca1b2a-e268-4245-a232-87c21526f91c', 'Sustain 1', 660, 380, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('823bd618-3a28-4dd9-a656-80e79f37f71e', 'Balanced', 754, 89, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4b8c5e83-94b0-4d25-91d5-dce51847e2d7', 'Australian Shares', 828, 98, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a2993fc9-5ec9-4199-b690-25acbc9cfcfc', 'Balanced Growth', 686, 389, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5b4b5bcc-f245-4e15-927d-52e5202f5c2f', 'Balanced low cost', 859, 103, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('68fc87f3-ab6a-4260-ba24-082a452197d0', 'Balanced', 8968, 123, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('53bc55c3-a119-41c3-97aa-0a4e547f08e4', 'Australian Dividend Income', 815, 97, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('48fdaa9e-8957-4761-b60b-ad0d7544feaf', 'Growth', 943, 122, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('07df4127-0ec6-4a14-945e-9595c6dc8694', 'Australian Equities 2', 14258, 148, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0e12dc40-3ad7-4519-b4ca-110dadde5d8c', 'Long-Term', 1037, 448, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7d47bdc6-8e0a-4918-9211-b9dc774997f5', 'International Shares', 829, 98, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d24c3508-d1ad-4141-89e2-f3fe9ccf4105', 'Defensive', 691, 390, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c3f30427-083c-4b81-8ea0-7af3067866c5', 'Conservative', 1032, 447, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f77a54fe-1eb2-4418-81b0-1d7c35ccf83e', 'Balanced', 671, 79, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1473568d-efde-46d6-b0e8-a3b573ba3e08', 'Australian Shares', 693, 81, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a14c8dad-8bed-4fd1-865d-14a27dea2956', 'Growth', 822, 98, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b4302b33-ae3c-4139-84e3-98fb2c2fb3cc', 'Indexed Defensive', 8969, 123, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('fd0eded0-6a59-47d2-a87a-533894537bc1', 'Moderate', 1033, 447, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e01d2257-46e8-4296-9640-24ed557cecb7', 'Sustain 2', 661, 380, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f969c2f2-0f9d-4a9d-8cad-c1e26f76cb53', 'Australian Shares', 790, 94, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e97020e8-39e5-4af0-9bd7-b543214afce5', 'Australian Shares', 812, 97, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e38e892d-d182-4114-9c5f-9ea82d7b4183', 'Moderate', 1031, 123, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('fdd41dfd-3f76-4fcb-a343-9baa33873549', 'Cash', 867, 102, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6f3d99e5-3cbd-4358-87cf-afdfd6a54b19', 'International Shares', 1041, 448, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('fe9939a8-20d5-48c5-85fc-21b18d37195c', 'Global Property', 678, 79, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('15776723-8434-4930-add1-2553916be96a', 'Cash', 817, 98, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('bacdeef7-b5f4-4f73-8436-28fcde5c50d5', 'Australian Equities', 14257, 148, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('251101ff-e96f-4638-a9b3-30f8a81e6fd4', 'High Growth', 823, 98, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('81a4c012-4e0c-4609-9082-590c74c27b69', 'Moderate', 13572, 122, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2c9378b7-1b44-492e-80b9-dbaddd1c3454', 'Mysuper Conservative', 795, 94, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9207287f-c515-4a95-9aab-f2644b93b892', 'MySuper Moderate', 14009, 94, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('68d01954-ca66-4a6b-8549-ad8ecf4a21bb', 'Growth', 684, 390, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b870466b-a159-47b8-a3de-12294d620b72', 'Indexed Australian Listed Property', 852, 101, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ec5eb1bb-c052-4ac3-abfc-5fc53e855ce0', 'Overseas shares - Indexed', 38, 381, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6347fde5-5ef1-4d7b-9d7c-7c54eb6926fd', 'Global Index', 968, 126, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f659c42e-49e2-48dc-97a5-2d3817aea3cd', 'Australian Equities', 864, 104, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7ebfe2df-dd82-4659-a782-51624812b553', 'Balanced Growth', 686, 81, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f68e01b9-52d4-4553-a988-62a2cd5fa343', 'Diversified Fixed Interest', 14262, 148, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('cad96ec6-4748-4ccb-89e6-7b49e6282c55', 'Balanced', 860, 103, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('447fed82-fd43-4ed7-82ff-0bf54da3b468', 'Balanced Growth', 858, 104, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0eea2d6c-c478-4c3b-9d52-3cd217560d79', 'Cash', 950, 122, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b35e8068-a019-491e-b181-0029a34b931b', 'Bonds', 679, 79, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('de1bbd69-291b-4d57-9926-bf5387f84f2d', 'Indexed Diversified Shares', 849, 101, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4394da61-542b-4ab2-a42d-a901402703bf', 'Stable', 756, 89, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c25c06a8-d4ee-459e-a5c4-e3feab906282', 'Cash', 801, 97, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('54538948-df93-4e66-a3d6-94c27d8f4187', 'Born 1964-1968', 843, 101, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ee3156c6-2a90-4ae5-91c9-32c26338544f', 'Balanced Growth', 686, 390, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2124aea7-fe1f-47b7-807f-851604b3598b', 'Mysuper Growth', 793, 93, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6badd0a2-eb75-4f77-ab62-2067f7c12be5', 'Balanced', 26, 381, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('63d6d64e-b555-42a2-ab17-99f50d02ddc7', 'Cash', 785, 93, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('02f7c630-20aa-4a64-b65c-82e46876324a', 'Australian Shares', 1040, 448, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9fb32f75-329a-4cbf-9d7b-50b5e399d462', 'International Shares', 698, 81, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('95d87f81-a6ae-46fb-a5f6-7869e09799d8', 'Sustainable High Growth', 808, 97, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e11cccfd-9d93-4afc-b994-1d21fc2e1bd8', 'Conservative', 788, 397, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('cd20db86-4bc7-491e-91bb-fe38805ac0e7', 'Australian Shares', 16896, 137, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('41c1aed9-b4fa-4078-8e23-2e1da4d0de70', 'Growth', 796, 94, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('455455be-f8a5-43f6-9a4d-207b6d35e63c', 'Moderate', 689, 390, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1a681da3-796d-4580-9bbd-9ca8ab560fae', 'Balanced', 1034, 447, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('53d14d7d-ee9f-4864-9a1c-3086381cc27c', 'Australian Property', 677, 80, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f391ae68-8166-433c-9cec-a4470a4746a2', 'High Growth', 14008, 94, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('218f3bb3-540d-4f14-b60c-44f1179bd787', 'Balanced', 671, 80, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('30b0a45a-6a4d-4148-8699-1e2a30640eb0', 'Born prior to 1949', 847, 101, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('615f57f6-fcc0-46b5-b19a-92d52308b90c', 'Global Property', 678, 80, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5aa18a6d-1f37-4b76-8fe3-edcdb8a86103', 'Defined Benefit', 15037, 93, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0f93f4c0-ab4f-49ba-8245-5017680cf6ec', 'Mysuper Conservative', 795, 397, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ba473cc4-6bff-45ac-a5b7-cb1cdc65d542', 'Indexed Overseas Shares', 851, 101, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1df6f1f9-b330-48e5-8290-a3d967332c39', 'Enhanced Indexed Growth', 853, 101, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('637cd366-7e25-48f5-8e84-dd674b6d86dd', 'High Growth', 1030, 123, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2f809bf2-6d81-498b-a585-ce519105c87f', 'Growth', 1036, 447, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7515aa1a-6b0e-415b-abeb-e10d29897f57', 'Balanced', 893, 109, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7d9d6bb5-444f-456b-af14-df1151f6a63c', 'Diversified Fixed Interest', 1039, 448, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('73c752d5-22d6-4110-8181-1ff6d2673965', 'Conservative', 899, 110, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('011a9c51-9fcf-4608-9e2d-3bca18f337c4', 'Balanced', 8966, 122, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4fe00119-4b91-4e13-a219-0df0b3b4ca50', 'Australian Shares', 790, 93, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3e7e1d13-f659-4882-b27a-940e7d2f901a', 'Enhanced Indexed Conservative Growth', 854, 101, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0b5e1082-0246-4cbf-8656-b51fa59b8541', 'International Shares', 676, 79, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('220eb838-ce22-4a74-a473-89005ac272f2', 'Growth', 684, 81, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4bde2d92-a68f-4255-a20f-e4c28b148ffb', 'International Shares', 698, 390, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a83ac9ea-eec2-4d06-b0ff-ea4b8927d26f', 'Cash', 867, 104, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9f911db8-d236-4ab8-b2ff-d5ff2aee6782', 'Australian Income', 826, 98, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a69d548f-81dc-4834-8d12-967bdf55c18f', 'International Shares', 903, 110, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5107777a-9fb6-4c4d-90db-1357d9ea2e41', 'Balanced', 797, 93, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2fb48fe6-9297-4263-91a8-6f92fd8eeef3', 'Balanced', 797, 94, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('08c6af90-3304-4fb0-a800-f5b77589a9fa', 'International Shares', 954, 123, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6f4ff0ed-f876-4557-ac1b-cacc4d24a6ad', 'Capital Stable', 25, 381, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b6887c71-ecba-40ae-b2f6-1532a7eb281f', 'Property', 948, 122, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c0c09f63-c3b9-4e66-aac3-c08d42d94fae', 'International Shares', 676, 80, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d007f47a-e33a-49c0-bc12-1f28bae9843c', 'Australia Post Defined Benefit', 15044, 88, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a6f1e32a-409c-475a-a9f8-069a63013d42', 'Conservative', 802, 97, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4ff30ef0-ba56-4e0b-870b-86cc86f9c461', 'Growth - Indexed', 27, 381, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('cfe6d9a4-99fa-46a9-a9b4-69676bbd5421', 'Moderate', 1033, 448, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2b8bd4a9-0316-4fd8-bd22-ac7eac8809ea', 'Conservative', 788, 94, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('8a137320-29dc-4b9b-8f38-e46bcb3c6cd7', 'Cash', 1038, 448, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ab377e68-ae97-4154-b27d-bb0415ce9b49', 'Defensive', 891, 109, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('cf79be20-adef-4b5b-8609-ef06f16f74d6', 'Pre-mixed Balanced', 14267, 148, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ac3ffb31-1417-4d12-b77e-5a0330e62f37', 'Sustainable Balanced', 805, 97, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7eb664d2-3d1e-40c1-8350-d8e410338e7c', 'Defensive', 13573, 122, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2b64dd28-0e11-414a-9aff-dbb0d02ba648', 'International Shares', 896, 110, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('be675551-9a89-4641-a8b8-bda677f194c7', 'Cash', 674, 79, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c91c869d-b443-477a-892b-0c6a0084d03d', 'Growth', 796, 93, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('292a2950-0a92-481e-8a6c-b02a56bb4e7a', 'Australian Bond', 809, 97, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('73987778-f039-496d-ba27-c5faef32e313', 'International Shares', 813, 97, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('27d12f10-0ff6-4a93-8e25-ee5716794655', 'International Shares Unhedged Index', 13865, 380, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ea428952-52a8-417b-94a0-835623a6e39d', 'Cash', 69, 155, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0bf2146f-c2da-4e80-966f-3d3ebfaddd82', 'Balanced low cost', 859, 102, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0f24f1dc-c5fc-4630-8fd0-cd3d6903305a', 'Conservative', 818, 98, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('654d9e12-e3e9-4ec5-bea5-44750c663bf4', 'Growth Plus', 14134, 79, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('cbded03d-a5fd-436f-b15a-e75c242404a1', 'Balanced', 860, 102, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3a73ad08-1718-43d5-affb-cf47f234c066', 'AMG Index Fixed Interest', 9779, 135, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a71da321-7385-4226-ba68-353a8dff526e', 'Balanced', 860, 104, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2c34a36e-41d1-4233-846f-cce334631627', 'Balanced low cost', 859, 104, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ab88df0d-890f-439a-8332-cc6498e03f5b', 'AMG Index Balanced', 9776, 135, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5299aa10-c6a7-42dc-b3ac-cb622512f8d4', 'Indexed Australian Shares', 850, 101, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e7ce97d9-0c77-40ea-b02d-c6c26b5acaa2', 'Australian Shares', 693, 390, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('41c22edf-29f8-4ae9-b7d8-a4fabc6c1f59', 'High Growth', 682, 389, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('656f1c80-f0ec-4de9-a271-d36ead68fd42', 'Balanced', 804, 97, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c829dcf1-9927-487f-99f1-be5d0f727c42', 'Conservative', 14261, 148, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5397540e-cb81-4a8b-bc80-cb6d02cdaed8', 'Moderate', 689, 389, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f96f5766-cd5a-475e-9572-346d8f92be5f', 'Growth', 857, 102, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a3000dc1-49d0-4e48-a0bf-90bd2beedf9e', 'Bonds', 679, 80, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('8ef38c6e-32ba-4cd8-84a1-98f90730b16f', 'Diversified Bonds and Credit', 792, 93, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ea99397a-12b9-4afb-b6be-55b0fd3ce175', 'Secure', 9153, 122, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('67ff66c2-5060-409a-8f3f-4d5dfd437b32', 'High Growth', 14008, 397, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('016876ef-a3b6-4c34-b1e8-201511783493', 'MySuper Moderate', 14009, 93, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d23df1cf-62df-402f-8322-f844100f11a2', 'Innovation and Disruption', 863, 103, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4206ca54-b109-43be-adc9-e75b417d616e', 'High Growth', 1016, 100, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9cf42f36-6ac9-41ac-86e8-b686a6c29f6f', 'AMG Index Fixed Interest', 9779, 136, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('00f5054f-120d-438e-9cd5-ab9343893119', 'Growth', 857, 103, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('89512090-b982-477c-9bf9-78e614ccbdf8', 'Term Deposit', 834, 99, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a4ef709b-771a-485e-9e6f-3501fe6bfc1a', 'Cash', 758, 89, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('dedc261b-47d9-4a16-8533-114d5c34d923', 'Socially Responsible', 752, 89, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('8c167a7c-fbe7-4ce5-9cd1-7b3f1b72d992', 'Balanced', 1034, 448, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6476e625-8dc0-45f9-8c43-5b6f369f54d7', 'International Shares - Index (unhedged)', 743, 87, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('863fc960-d2b8-4d2a-874a-4566c0fcd5c4', 'Australian Property', 677, 79, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('989b0234-e223-43e2-b010-13b4db84f828', 'AMP Retirement Savings Account', 9052, 145, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('36cdfefa-b508-438e-b097-c2d7b1feba73', 'Socially Conscious Balanced', 13860, 380, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b906a189-57e8-44ba-aa7e-9aedcedeaebd', 'Cash', 680, 390, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('27e2505e-1dfa-4d92-bdc1-89146e100cbf', 'AMG Index International Equities', 9781, 135, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('44c01948-038e-4db9-917f-cdd5860d2184', 'Conservative', 1021, 100, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('08e6a63b-bef0-4344-b9ed-08bf88f0895e', 'Australian Shares', 904, 110, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('70282814-86a4-4202-bbe6-1d5abb918737', 'Capital Stable', 56, 137, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('8eb50f93-9d0e-4c14-a66a-2f56fd0ada21', 'Bonds', 10437, 99, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('631df789-cb59-4f18-938f-6f2e412750a6', 'Australian Equities 3', 14259, 148, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('81e06cd1-a3a6-4679-aa43-63a18fecb654', 'High Growth', 14008, 93, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a0f59a49-39ae-4c14-876f-638bef461be5', 'Term Deposit', 951, 122, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('bff4321b-abe4-420a-9315-7a722532d16d', 'Australian Shares', 946, 122, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9cc3c85b-e314-4cb6-a3ef-c4a23472690b', 'Cash', 680, 81, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('09aa494a-e391-4471-b2f0-014b10c28fcf', 'Mysuper Balanced', 794, 93, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('25ce8561-2f90-4049-b55c-c7f1752d0471', 'Balanced Growth', 858, 103, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('bad6a7e8-25a8-4c6e-a227-cb2dddeb1fae', 'International Shares', 16897, 137, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('cdbddaf3-bcac-4577-abe4-271081beca9f', 'Specialised International Share', 14270, 148, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('964d8dfd-7af2-4d77-904e-bb40684f5a21', 'Growth', 24, 381, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('11e98fc4-d9cf-44cb-a21b-458611cf7a8c', 'Diversified High Growth', 14264, 148, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a73c5cdc-88ac-4b2f-a972-b777a20c7ee5', 'Moderate', 787, 94, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c6cfc6b2-4ea4-4de8-9db4-4d4af53f8350', 'Growth', 1036, 448, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('48908eb6-ffc3-41b0-a0bf-ae3adfa55846', 'Cash', 749, 87, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0cd12be1-9cc4-4893-a065-bbd8dacf4563', 'Growth', 796, 397, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('24869d6c-d228-4f62-9c83-365b88a15478', 'Sustainable High Growth', 824, 98, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('183a0202-96b2-44e3-8e1e-c13a46d6d6ab', 'Defined Benefit', 15037, 397, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1b23413c-e5a9-49d7-8f99-411e52f22d7d', 'Sustainable', 1035, 447, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('fa3452d2-8b92-4198-817e-00db20e11b7e', 'Cash', 785, 94, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('292faca7-99f0-4369-ac4d-3aeda3bc0624', 'AMG Index Listed Property', 9782, 135, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('85634a42-0648-46b0-a847-f01ebcf000b2', 'Australian Shares', 675, 79, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3585952b-0866-4572-ab09-073c87d522ba', 'Mysuper Balanced', 794, 94, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0dfc79db-7dcc-414e-a4b2-256f6efd21d4', 'High Growth', 807, 97, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d5fd944a-154b-48fe-b60b-740dbbf407fb', 'Balanced', 820, 98, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6e48fe4b-ba46-442f-8c86-cd312a611080', 'Property', 955, 123, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6057feb0-ecce-4cb6-afa7-2330d99f1f07', 'Cash', 31, 381, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2674fb59-92d3-46c0-9904-7124f9a09593', 'Innovation and Disruption', 863, 102, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a0559a85-bb13-4a48-bbef-a312c3aa0f9e', 'High Growth', 840, 99, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('46513a0e-7830-4997-849a-f515fad8581b', 'Growth', 901, 110, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c23f94d8-06b5-42b6-b8af-747d382a4aea', 'Property', 996, 137, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('95b8d07d-0596-4a5b-b253-79aff063ec09', 'Balanced', 797, 397, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('55343195-b6f6-48c3-9a09-0c74651227f2', 'Australian Shares', 953, 123, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('41d17449-2a35-43fb-8342-c9185ae30492', 'AMG Index International Equities', 9781, 136, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4fe27009-d292-4728-95a4-b0eb8fd5a228', 'Australian Income', 810, 97, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('51667bcc-3755-4f6d-8395-0f0f05e487c2', 'UniSuper Defined Benefit', 12240, 401, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3c4f09ff-c2c2-4f3d-9ce3-92ac88074748', 'Listed Property Index', 13866, 380, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('008692ba-63b1-4f59-a3c1-8b3362589fb0', 'Diversified Growth', 14263, 148, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('bb24efad-7dd1-45c7-8592-a752bbd45be7', 'High Growth', 751, 89, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('aca67291-b629-4932-a65b-37ec48c06a28', 'Stable', 672, 80, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5a1b999d-1dc1-43de-9a95-314f00857951', 'Wholesale Global Equity Fund', 14271, 148, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b363f486-bdf6-4141-a8a5-dbadb1293ba5', 'Growth', 959, 123, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('382337ce-ebb1-4c84-b7b1-1517bd187768', 'Stable', 672, 79, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('080d3376-00ca-4761-9e38-304b06b97f51', 'Listed Property', 811, 97, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('405cab33-f38c-4694-9b94-9095c2e76f83', 'Defensive', 835, 99, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('8faccce3-47d3-4d6e-b5a5-08302ce64453', 'Outlook', 655, 380, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('39de0597-3e37-48dc-9ea8-a35be0ea673e', 'Listed Property Index', 746, 87, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7a081100-7a06-4643-b3a1-780608107570', 'Conservative', 1032, 448, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5c9a2039-0d6a-4aa8-9806-28941ed3596a', 'Growth', 894, 109, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e7357c11-1624-48e1-9dbe-3cbe53e1c90e', 'Australian Shares - Index', 741, 87, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('938151ba-91aa-4877-b21c-9a2fd495e5ff', 'High Growth', 895, 110, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4a3c56d9-443b-4a0f-bbd0-d18d122f0fb8', 'International Shares', 947, 122, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('52bed630-c142-4b8f-a5dd-c9f01c956f3c', 'Spaceship Balanced Option', 16320, 126, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('4ba3756b-eb75-4d24-b91a-42fc6ea3b374', 'Growth', 58, 137, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9a81b234-86b3-4871-83b8-d7bd990c27f7', 'Conservative', 861, 104, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e45cfa0f-4ac3-4ea1-8786-7cf0d4456b65', 'International Shares Index', 13864, 380, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f8680f62-26ff-4860-bdbc-082c1e7facb1', 'Long-Term', 1037, 447, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5b9ac8e6-43b1-4ee2-bcca-80e6919718b3', 'Diversified Fixed Interest', 1039, 447, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b2abf39c-9e4b-4ded-a4fa-af97572ecf0f', 'Australian Equities', 864, 103, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('75407824-75e3-49ef-af73-9329d89f949f', 'Conservative', 788, 93, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5e0d60d1-7ebc-4b69-9aef-0720c5618cac', 'Sustain 3', 13856, 380, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b57eed00-b2df-48a1-b128-14328b86b4f1', 'Listed Property', 827, 98, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7173091d-e258-484e-afbb-2ff406d07adf', 'AMG Index Cash', 9783, 135, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ace795d9-d056-4575-8d70-5787aa3e6b25', 'Born 1959-1963', 844, 101, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('85bcdadb-4685-46fb-9f06-d7f5b99b10f5', 'Moderate Growth', 14266, 148, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0e8ffa0d-4889-4d2f-bc83-6b9a2747e399', 'International Shares', 698, 389, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('97c77828-f6be-40a3-8cf2-6a4374feb143', 'Sustainable', 1035, 448, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b750dda9-1507-479e-973c-a35de126e07b', 'Born after 1973', 842, 101, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('cda4dcb7-9c36-4d0e-bf11-b884eaad2571', 'Australian Shares', 790, 397, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('cc0c56a3-fd28-4dc0-952c-6caa20cfffd9', 'Balanced', 837, 99, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6d7208e1-9376-45e6-8312-293480caf900', 'Futurity Sectoral Active - Responsible Investment', 10688, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2fb4d4d4-df89-4e61-8fe9-1c705d78c8ee', 'Futurity Managed & Blended - Responsible Investment Portfolio', 8614, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b9bfcef8-df2d-4c27-b006-b538f490da88', 'Lifecycle 48', 10750, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('8fd90ae6-4f2a-496a-83ae-c758c308b7b3', 'Lifecycle 66', 10768, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('dad7407b-ca15-4402-8f32-1715aa10ce96', 'Sustainable Moderate', 16276, 592, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1f613895-9eaf-448b-9280-fcad396a5206', 'Lifecycle 66', 10768, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('eeee0986-d07f-459e-b5d3-e0880c14d6da', 'Futurity Diversified Active - High Growth', 8622, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('fe50d1a4-311d-4edc-a731-1bbbe77ec335', 'Sustainable High Growth', 16273, 592, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5a7759e7-1f19-4476-955f-3017de7503a4', 'Lifecycle 47 and below', 10749, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9532e0f5-0898-48f2-a794-2223c02ed20e', 'Lifecycle 63', 10765, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('95032dc5-1cf2-4c0b-a9c6-06fcfe63d859', 'Lifecycle 58', 10760, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2d719e23-be8e-4ede-9aa7-79cb12e6c2b8', 'Lifecycle 56', 10758, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('28d37386-7016-4617-b3a6-bed6680bc0b9', 'Lifecycle 60', 10762, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6cc9dd68-1819-4478-ba48-1524e753db25', 'Lifecycle 55', 10757, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2d478a8a-6f39-471c-979a-da2a23b702b9', 'Futurity Diversified Active - Balanced - 2', 10690, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('abda48d3-b0e3-4b94-a98c-b82b4156e8e1', 'Futurity Sectoral Active - Australian Equities', 8631, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7cb4cfc4-3c97-4b7b-9001-f8e1c3255a1f', 'Lifecycle 65', 10767, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d1ad86cb-0294-48b0-8e1a-6f35aa50ab59', 'Sustainable Growth', 15839, 452, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d4b8c06a-f7bd-491e-bcfe-2c4934eadd81', 'Lifecycle 47 and below', 10749, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c62e4aa7-f1be-4239-82d5-5748a6120e34', 'Lifecycle 58', 10760, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('349e8199-7f2d-4e16-b9e4-736b96947dc1', 'Lifecycle 56', 10758, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('cd875530-43f3-4df2-b31a-133dfce03670', 'Futurity Sectoral Active - Cash', 8629, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('be05a931-c22f-401c-bacf-3d13ff8fe2d8', 'Lifecycle 52', 10754, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('81a3ac51-96e2-4aa9-9193-2c40d8e3a91f', 'Futurity Managed & Blended - Balanced', 8612, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b2d9dd5e-2bad-4bd2-9de5-3bc7cd549efb', 'Futurity Sectoral Indexed - Responsible Investment', 8628, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a27f8f09-d2cf-4613-883f-dffb2a189324', 'International Shares', 10521, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3888f30e-8bd4-449f-8a38-fcc5fb67a3a3', 'Lifecycle 67', 10769, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d86eb8dc-5dd0-469d-af1c-d6ffeb67e391', 'Futurity Diversified Active - Conservative', 8619, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('fbb3097d-9992-40bb-81c5-a19ea996d619', 'Futurity Sectoral Active - International Equities', 8632, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('584d53e4-9590-496d-a727-54f4893297de', 'Futurity Sectoral Active - Emerging Market Equities', 8633, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('70940fb3-a875-4a52-bb00-57954fcd2ca8', 'Futurity Diversified Active - Growth - 3', 10693, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3472171a-a60e-42e6-a8d7-0143c1badc2e', 'Lifecycle 49', 10751, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('ce9e3767-b1c3-4585-9f4c-e0311b999544', 'High Growth', 10515, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c8b7fb04-0f85-43c7-86df-f10713550de9', 'Growth', 11383, 531, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('14f087cc-ef42-42e5-8cf1-67be6a6662e3', 'Lifecycle 60', 10762, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f023e908-81b8-4f02-afaa-e3a0c93dbf89', 'Lifecycle 64', 10766, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('8004b2eb-1e1a-41c8-8b2b-61d014cb7771', 'Lifecycle 51', 10753, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('33dae7dc-72ac-4250-a091-ec3473229664', 'Growth', 10517, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e4ab2718-4f50-4df2-ae15-b5611e7e225b', 'Futurity Diversified Active - Balanced', 8620, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3d58ac15-41fd-42bf-9f6d-324220d12647', 'Sustainable Moderate', 15841, 452, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('31feedae-6a76-4c3c-bf6f-4ece88c7e3b3', 'Lifecycle 54', 10756, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('aedc3079-80a3-4221-ade0-75f155cca715', 'Lifecycle 62', 10764, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('97fc0e69-2f8e-4853-982a-504c3da719ed', 'International Shares', 10521, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5d51fa14-aeac-4c64-a744-cac2e75818d8', 'Lifecycle 60', 10762, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b442e5a0-b3cf-4a25-a3d0-4e17b1063aec', 'Lifecycle 47 and below', 10749, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e4feb6e8-a3d3-40d2-b4a2-58645a8e15c5', 'Lifecycle 63', 10765, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1272a88d-1117-4543-84f9-1358cfd067f3', 'Lifecycle 61', 10763, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('9b6d7ec5-b990-49e0-a991-dae46acc4222', 'Futurity Diversified Indexed - Growth', 8617, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('82ec2bda-6acb-4385-a535-47a59034a519', 'Lifecycle 63', 10765, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('82606fe4-26cf-406f-a9af-bda91c292d6a', 'Futurity Diversified Active - Responsible Investment - 2', 10695, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c0d14e67-c54f-4ba3-866c-a27e16e85003', 'Lifecycle 62', 10764, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7a5f1478-cc45-4a73-ae58-4b8920d72dc1', 'Lifecycle 65', 10767, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b113a6ce-79db-4d94-9e90-ea3c34d53516', 'Futurity Diversified Indexed - High Growth', 8618, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('3d32452a-3fb8-4dcf-93b5-a2b973916327', 'Lifecycle 67', 10769, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6114a8ea-2789-411a-bc7c-aaa14d51fdc4', 'Lifecycle 50', 10752, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('eff8e77a-039c-4886-b5e1-5f87f6d56173', 'International Shares (hedged)', 10522, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('0e88591a-11c9-441f-88ba-cc57d4ee81ff', 'Balanced', 11382, 531, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('51b1c85d-e9fc-4b44-834d-edc18ce8084c', 'Futurity Diversified Active - Growth', 8621, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('577e1b25-4f67-463c-9e3a-0fe8d911be31', 'Lifecycle 59', 10761, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c8a23bb1-0ae4-44d7-955d-bf00105fea5c', 'International Shares (hedged)', 10522, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('1e794ea4-33fc-4dfa-bc21-44754766f678', 'Futurity Diversified Active - Responsible Investment', 10692, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('435affb3-a3e2-487b-878d-0b9d497be671', 'Futurity Sectoral Indexed - Australian Fixed Income', 8623, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('15a11b77-bc30-408b-91d1-b8f2b4bbf02a', 'Balanced', 754, 497, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d24064aa-d476-46fd-9491-5de6ba7986bb', 'Global Fixed Interest (hedged)', 10524, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('d74d35d2-af91-458f-85e5-c3f69d93b94b', 'Lifecycle 51', 10753, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('dac7dad2-c2f8-41a0-ad20-9dc02cd60f74', 'Lifecycle 57', 10759, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('fddf05fc-b696-4d7e-82fe-60749876ccde', 'International Shares (hedged)', 10522, 502, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('bf878f8e-78b4-4d90-a165-0a80a9c751a3', 'Australian Listed Property', 13075, 462, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('dd6252c8-42ea-4151-9a99-84df60294a2a', 'Growth', 10517, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('7deeb6e4-df2a-4db5-9030-90bcdeae3cf2', 'Lifecycle 50', 10752, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('8e6039a9-1526-49e4-b2ab-be287278a0ef', 'Lifecycle 48', 10750, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('926547ff-9786-4edf-9cc3-ce6a167ce2a6', 'Futurity Sectoral Indexed - Emerging Market Equities', 8626, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('e0bb82cb-ccbe-4f46-9327-a17e057c96ea', 'Lifecycle 53', 10755, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('8475171f-d5e3-431b-a047-1b5ad7ebdce5', 'Futurity Managed & Blended - Growth', 8613, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('c4b4ba0d-c303-4872-bbbd-9c74c116e4f6', 'Moderate', 11229, 496, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('361e9efe-688b-4d8e-8bbc-7160bfe2b4e6', 'Futurity Diversified Active - Growth - 2', 10691, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('f1a30700-6588-4548-9317-49bf565a5bea', 'Capital Defensive', 11231, 496, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('5ce57636-4c41-406c-baff-1ab0f98f230d', 'Lifecycle 56', 10758, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('06e24499-703c-4c17-b955-29372a981847', 'Global Healthcare', 13081, 462, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('2055f460-920b-42bd-9d1c-83d27b2a4583', 'Global Sustainability Leaders (unhedged)', 13082, 577, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('b0868aae-7948-4803-92af-dace02c68535', 'Futurity Diversified Indexed - Conservative', 8615, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('a8dc58d1-d5bf-40d4-8b52-30e63e0772d6', 'Futurity Sectorial Indexed - International Fixed Income', 10696, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('05b2e322-bd86-406b-ba45-c958e9cf10e4', 'International Shares', 13073, 462, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6a85ecfd-fb13-43d6-b726-631efd136600', 'Futurity Sectoral Active - Responsible Investment - 2', 10689, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('03362656-5d5c-4c17-9d59-a4e8409017ba', 'Lifecycle 52', 10754, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('72865cc0-47d7-4b5e-b6dc-1295c9038b71', 'Sustainable Growth', 16274, 592, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('74e9689e-84ed-4032-8744-9e2a868e0745', 'Lifecycle 48', 10750, 545, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('04137293-984b-4f7c-853d-cd7bc4bb7c7e', 'Australian Fixed Interest', 13076, 577, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('6386cb3a-c238-4674-9a84-43de7510f0e4', 'Lifecycle 61', 10763, 544, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('baafdb96-4410-4ca9-bfda-328274c0afe8', 'Futurity Sectoral Active - Australian Fixed Income', 8630, 460, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('bdfa24df-2fcf-43c8-8d0d-7de1a10e3cc6', 'High Growth', 751, 497, 1.00000000);
INSERT INTO public.investment_option (investment_option_id, name, rex_id, linked_product, current_price) VALUES ('dab2ac8f-4ebd-47cb-9fcf-4037c479938b', 'Lifecycle 66', 10768, 502, 1.00000000);


--
-- Name: advice_case_number_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.advice_case_number_seq', 1005, true);


--
-- Name: business_unit business_unit_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.business_unit
    ADD CONSTRAINT business_unit_pkey PRIMARY KEY (id);


--
-- Name: case_entity case_entity_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.case_entity
    ADD CONSTRAINT case_entity_pkey PRIMARY KEY (case_id, entity_id);


--
-- Name: case_financial_planner case_financial_planner_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.case_financial_planner
    ADD CONSTRAINT case_financial_planner_pkey PRIMARY KEY (case_id, financial_planner_id);


--
-- Name: contact contact_entity_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contact
    ADD CONSTRAINT contact_entity_unique UNIQUE (entity_id);


--
-- Name: contact contact_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contact
    ADD CONSTRAINT contact_pkey PRIMARY KEY (id);


--
-- Name: crm_case crm_case_case_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.crm_case
    ADD CONSTRAINT crm_case_case_number_key UNIQUE (case_number);


--
-- Name: crm_case crm_case_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.crm_case
    ADD CONSTRAINT crm_case_pkey PRIMARY KEY (id);


--
-- Name: crm_migration crm_migration_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.crm_migration
    ADD CONSTRAINT crm_migration_pkey PRIMARY KEY (name);


--
-- Name: crm_note crm_note_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.crm_note
    ADD CONSTRAINT crm_note_pkey PRIMARY KEY (id);


--
-- Name: crm_task crm_task_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.crm_task
    ADD CONSTRAINT crm_task_pkey PRIMARY KEY (id);


--
-- Name: entity entity_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.entity
    ADD CONSTRAINT entity_pkey PRIMARY KEY (id);


--
-- Name: entity_relationship entity_relationship_from_entity_id_to_entity_id_relationshi_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.entity_relationship
    ADD CONSTRAINT entity_relationship_from_entity_id_to_entity_id_relationshi_key UNIQUE (from_entity_id, to_entity_id, relationship_type);


--
-- Name: entity_relationship entity_relationship_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.entity_relationship
    ADD CONSTRAINT entity_relationship_pkey PRIMARY KEY (id);


--
-- Name: fact_find_beneficiary fact_find_beneficiary_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_beneficiary
    ADD CONSTRAINT fact_find_beneficiary_pkey PRIMARY KEY (id);


--
-- Name: fact_find_business_income_ownership fact_find_business_income_own_business_income_id_contact_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_business_income_ownership
    ADD CONSTRAINT fact_find_business_income_own_business_income_id_contact_id_key UNIQUE (business_income_id, entity_id);


--
-- Name: fact_find_business_income_ownership fact_find_business_income_ownership_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_business_income_ownership
    ADD CONSTRAINT fact_find_business_income_ownership_pkey PRIMARY KEY (id);


--
-- Name: fact_find_business_income fact_find_business_income_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_business_income
    ADD CONSTRAINT fact_find_business_income_pkey PRIMARY KEY (id);


--
-- Name: fact_find_cash_ownership fact_find_cash_ownership_cash_id_contact_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_cash_ownership
    ADD CONSTRAINT fact_find_cash_ownership_cash_id_contact_id_key UNIQUE (cash_id, entity_id);


--
-- Name: fact_find_cash_ownership fact_find_cash_ownership_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_cash_ownership
    ADD CONSTRAINT fact_find_cash_ownership_pkey PRIMARY KEY (id);


--
-- Name: fact_find_cash fact_find_cash_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_cash
    ADD CONSTRAINT fact_find_cash_pkey PRIMARY KEY (id);


--
-- Name: fact_find_centrelink_income_ownership fact_find_centrelink_income_o_centrelink_income_id_contact__key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_centrelink_income_ownership
    ADD CONSTRAINT fact_find_centrelink_income_o_centrelink_income_id_contact__key UNIQUE (centrelink_income_id, entity_id);


--
-- Name: fact_find_centrelink_income_ownership fact_find_centrelink_income_ownership_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_centrelink_income_ownership
    ADD CONSTRAINT fact_find_centrelink_income_ownership_pkey PRIMARY KEY (id);


--
-- Name: fact_find_centrelink_income fact_find_centrelink_income_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_centrelink_income
    ADD CONSTRAINT fact_find_centrelink_income_pkey PRIMARY KEY (id);


--
-- Name: fact_find_credit_card_ownership fact_find_credit_card_ownership_credit_card_id_contact_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_credit_card_ownership
    ADD CONSTRAINT fact_find_credit_card_ownership_credit_card_id_contact_id_key UNIQUE (credit_card_id, entity_id);


--
-- Name: fact_find_credit_card_ownership fact_find_credit_card_ownership_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_credit_card_ownership
    ADD CONSTRAINT fact_find_credit_card_ownership_pkey PRIMARY KEY (id);


--
-- Name: fact_find_credit_card fact_find_credit_card_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_credit_card
    ADD CONSTRAINT fact_find_credit_card_pkey PRIMARY KEY (id);


--
-- Name: fact_find_direct_investment_item fact_find_direct_investment_item_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_direct_investment_item
    ADD CONSTRAINT fact_find_direct_investment_item_pkey PRIMARY KEY (id);


--
-- Name: fact_find_direct_investment_ownership fact_find_direct_investment_o_direct_investment_id_contact__key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_direct_investment_ownership
    ADD CONSTRAINT fact_find_direct_investment_o_direct_investment_id_contact__key UNIQUE (direct_investment_id, entity_id);


--
-- Name: fact_find_direct_investment_ownership fact_find_direct_investment_ownership_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_direct_investment_ownership
    ADD CONSTRAINT fact_find_direct_investment_ownership_pkey PRIMARY KEY (id);


--
-- Name: fact_find_direct_investment fact_find_direct_investment_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_direct_investment
    ADD CONSTRAINT fact_find_direct_investment_pkey PRIMARY KEY (id);


--
-- Name: fact_find_expense_ownership fact_find_expense_ownership_expense_id_contact_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_expense_ownership
    ADD CONSTRAINT fact_find_expense_ownership_expense_id_contact_id_key UNIQUE (expense_id, entity_id);


--
-- Name: fact_find_expense_ownership fact_find_expense_ownership_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_expense_ownership
    ADD CONSTRAINT fact_find_expense_ownership_pkey PRIMARY KEY (id);


--
-- Name: fact_find_expense fact_find_expense_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_expense
    ADD CONSTRAINT fact_find_expense_pkey PRIMARY KEY (id);


--
-- Name: fact_find_fixed_interest_ownership fact_find_fixed_interest_owner_fixed_interest_id_contact_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_fixed_interest_ownership
    ADD CONSTRAINT fact_find_fixed_interest_owner_fixed_interest_id_contact_id_key UNIQUE (fixed_interest_id, entity_id);


--
-- Name: fact_find_fixed_interest_ownership fact_find_fixed_interest_ownership_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_fixed_interest_ownership
    ADD CONSTRAINT fact_find_fixed_interest_ownership_pkey PRIMARY KEY (id);


--
-- Name: fact_find_fixed_interest fact_find_fixed_interest_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_fixed_interest
    ADD CONSTRAINT fact_find_fixed_interest_pkey PRIMARY KEY (id);


--
-- Name: fact_find_foreign_income_ownership fact_find_foreign_income_owner_foreign_income_id_contact_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_foreign_income_ownership
    ADD CONSTRAINT fact_find_foreign_income_owner_foreign_income_id_contact_id_key UNIQUE (foreign_income_id, entity_id);


--
-- Name: fact_find_foreign_income_ownership fact_find_foreign_income_ownership_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_foreign_income_ownership
    ADD CONSTRAINT fact_find_foreign_income_ownership_pkey PRIMARY KEY (id);


--
-- Name: fact_find_foreign_income fact_find_foreign_income_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_foreign_income
    ADD CONSTRAINT fact_find_foreign_income_pkey PRIMARY KEY (id);


--
-- Name: fact_find_home_contents_ownership fact_find_home_contents_ownersh_home_contents_id_contact_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_home_contents_ownership
    ADD CONSTRAINT fact_find_home_contents_ownersh_home_contents_id_contact_id_key UNIQUE (home_contents_id, entity_id);


--
-- Name: fact_find_home_contents_ownership fact_find_home_contents_ownership_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_home_contents_ownership
    ADD CONSTRAINT fact_find_home_contents_ownership_pkey PRIMARY KEY (id);


--
-- Name: fact_find_home_contents fact_find_home_contents_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_home_contents
    ADD CONSTRAINT fact_find_home_contents_pkey PRIMARY KEY (id);


--
-- Name: fact_find_insurance_policy_feature fact_find_insurance_policy_feature_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_insurance_policy_feature
    ADD CONSTRAINT fact_find_insurance_policy_feature_pkey PRIMARY KEY (id);


--
-- Name: fact_find_insurance_policy_item fact_find_insurance_policy_item_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_insurance_policy_item
    ADD CONSTRAINT fact_find_insurance_policy_item_pkey PRIMARY KEY (id);


--
-- Name: fact_find_insurance_policy_ownership fact_find_insurance_policy_ow_insurance_policy_id_contact_i_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_insurance_policy_ownership
    ADD CONSTRAINT fact_find_insurance_policy_ow_insurance_policy_id_contact_i_key UNIQUE (insurance_policy_id, entity_id);


--
-- Name: fact_find_insurance_policy_ownership fact_find_insurance_policy_ownership_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_insurance_policy_ownership
    ADD CONSTRAINT fact_find_insurance_policy_ownership_pkey PRIMARY KEY (id);


--
-- Name: fact_find_insurance_policy fact_find_insurance_policy_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_insurance_policy
    ADD CONSTRAINT fact_find_insurance_policy_pkey PRIMARY KEY (id);


--
-- Name: fact_find_investment_holding fact_find_investment_holding_investment_platform_id_investm_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_investment_holding
    ADD CONSTRAINT fact_find_investment_holding_investment_platform_id_investm_key UNIQUE (investment_platform_id, investment_option_id);


--
-- Name: fact_find_investment_holding fact_find_investment_holding_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_investment_holding
    ADD CONSTRAINT fact_find_investment_holding_pkey PRIMARY KEY (id);


--
-- Name: fact_find_investment_holding fact_find_investment_holding_retirement_asset_id_investment_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_investment_holding
    ADD CONSTRAINT fact_find_investment_holding_retirement_asset_id_investment_key UNIQUE (retirement_asset_id, investment_option_id);


--
-- Name: fact_find_investment_holding fact_find_investment_holding_superannuation_id_investment_o_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_investment_holding
    ADD CONSTRAINT fact_find_investment_holding_superannuation_id_investment_o_key UNIQUE (superannuation_id, investment_option_id);


--
-- Name: fact_find_investment_income_ownership fact_find_investment_income_o_investment_income_id_contact__key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_investment_income_ownership
    ADD CONSTRAINT fact_find_investment_income_o_investment_income_id_contact__key UNIQUE (investment_income_id, entity_id);


--
-- Name: fact_find_investment_income_ownership fact_find_investment_income_ownership_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_investment_income_ownership
    ADD CONSTRAINT fact_find_investment_income_ownership_pkey PRIMARY KEY (id);


--
-- Name: fact_find_investment_income fact_find_investment_income_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_investment_income
    ADD CONSTRAINT fact_find_investment_income_pkey PRIMARY KEY (id);


--
-- Name: fact_find_investment_platform_ownership fact_find_investment_platform_investment_platform_id_contac_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_investment_platform_ownership
    ADD CONSTRAINT fact_find_investment_platform_investment_platform_id_contac_key UNIQUE (investment_platform_id, entity_id);


--
-- Name: fact_find_investment_platform_item fact_find_investment_platform_item_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_investment_platform_item
    ADD CONSTRAINT fact_find_investment_platform_item_pkey PRIMARY KEY (id);


--
-- Name: fact_find_investment_platform_ownership fact_find_investment_platform_ownership_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_investment_platform_ownership
    ADD CONSTRAINT fact_find_investment_platform_ownership_pkey PRIMARY KEY (id);


--
-- Name: fact_find_investment_platform fact_find_investment_platform_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_investment_platform
    ADD CONSTRAINT fact_find_investment_platform_pkey PRIMARY KEY (id);


--
-- Name: fact_find_occupational_income_ownership fact_find_occupational_income_occupational_income_id_contac_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_occupational_income_ownership
    ADD CONSTRAINT fact_find_occupational_income_occupational_income_id_contac_key UNIQUE (occupational_income_id, entity_id);


--
-- Name: fact_find_occupational_income_ownership fact_find_occupational_income_ownership_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_occupational_income_ownership
    ADD CONSTRAINT fact_find_occupational_income_ownership_pkey PRIMARY KEY (id);


--
-- Name: fact_find_occupational_income fact_find_occupational_income_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_occupational_income
    ADD CONSTRAINT fact_find_occupational_income_pkey PRIMARY KEY (id);


--
-- Name: fact_find_other_asset_ownership fact_find_other_asset_ownership_other_asset_id_contact_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_other_asset_ownership
    ADD CONSTRAINT fact_find_other_asset_ownership_other_asset_id_contact_id_key UNIQUE (other_asset_id, entity_id);


--
-- Name: fact_find_other_asset_ownership fact_find_other_asset_ownership_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_other_asset_ownership
    ADD CONSTRAINT fact_find_other_asset_ownership_pkey PRIMARY KEY (id);


--
-- Name: fact_find_other_asset fact_find_other_asset_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_other_asset
    ADD CONSTRAINT fact_find_other_asset_pkey PRIMARY KEY (id);


--
-- Name: fact_find_other_income_ownership fact_find_other_income_ownership_other_income_id_contact_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_other_income_ownership
    ADD CONSTRAINT fact_find_other_income_ownership_other_income_id_contact_id_key UNIQUE (other_income_id, entity_id);


--
-- Name: fact_find_other_income_ownership fact_find_other_income_ownership_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_other_income_ownership
    ADD CONSTRAINT fact_find_other_income_ownership_pkey PRIMARY KEY (id);


--
-- Name: fact_find_other_income fact_find_other_income_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_other_income
    ADD CONSTRAINT fact_find_other_income_pkey PRIMARY KEY (id);


--
-- Name: fact_find_other_liability_ownership fact_find_other_liability_own_other_liability_id_contact_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_other_liability_ownership
    ADD CONSTRAINT fact_find_other_liability_own_other_liability_id_contact_id_key UNIQUE (other_liability_id, entity_id);


--
-- Name: fact_find_other_liability_ownership fact_find_other_liability_ownership_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_other_liability_ownership
    ADD CONSTRAINT fact_find_other_liability_ownership_pkey PRIMARY KEY (id);


--
-- Name: fact_find_other_liability fact_find_other_liability_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_other_liability
    ADD CONSTRAINT fact_find_other_liability_pkey PRIMARY KEY (id);


--
-- Name: fact_find_personal_loan_ownership fact_find_personal_loan_ownersh_personal_loan_id_contact_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_personal_loan_ownership
    ADD CONSTRAINT fact_find_personal_loan_ownersh_personal_loan_id_contact_id_key UNIQUE (personal_loan_id, entity_id);


--
-- Name: fact_find_personal_loan_ownership fact_find_personal_loan_ownership_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_personal_loan_ownership
    ADD CONSTRAINT fact_find_personal_loan_ownership_pkey PRIMARY KEY (id);


--
-- Name: fact_find_personal_loan fact_find_personal_loan_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_personal_loan
    ADD CONSTRAINT fact_find_personal_loan_pkey PRIMARY KEY (id);


--
-- Name: fact_find_principal_residence_ownership fact_find_principal_residence_ownership_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_principal_residence_ownership
    ADD CONSTRAINT fact_find_principal_residence_ownership_pkey PRIMARY KEY (id);


--
-- Name: fact_find_principal_residence fact_find_principal_residence_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_principal_residence
    ADD CONSTRAINT fact_find_principal_residence_pkey PRIMARY KEY (id);


--
-- Name: fact_find_principal_residence_ownership fact_find_principal_residence_principal_residence_id_contac_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_principal_residence_ownership
    ADD CONSTRAINT fact_find_principal_residence_principal_residence_id_contac_key UNIQUE (principal_residence_id, entity_id);


--
-- Name: fact_find_property_asset_ownership fact_find_property_asset_owner_property_asset_id_contact_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_property_asset_ownership
    ADD CONSTRAINT fact_find_property_asset_owner_property_asset_id_contact_id_key UNIQUE (property_asset_id, entity_id);


--
-- Name: fact_find_property_asset_ownership fact_find_property_asset_ownership_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_property_asset_ownership
    ADD CONSTRAINT fact_find_property_asset_ownership_pkey PRIMARY KEY (id);


--
-- Name: fact_find_property_asset fact_find_property_asset_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_property_asset
    ADD CONSTRAINT fact_find_property_asset_pkey PRIMARY KEY (id);


--
-- Name: fact_find_property_income_ownership fact_find_property_income_own_property_income_id_contact_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_property_income_ownership
    ADD CONSTRAINT fact_find_property_income_own_property_income_id_contact_id_key UNIQUE (property_income_id, entity_id);


--
-- Name: fact_find_property_income_ownership fact_find_property_income_ownership_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_property_income_ownership
    ADD CONSTRAINT fact_find_property_income_ownership_pkey PRIMARY KEY (id);


--
-- Name: fact_find_property_income fact_find_property_income_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_property_income
    ADD CONSTRAINT fact_find_property_income_pkey PRIMARY KEY (id);


--
-- Name: fact_find_property_loan_ownership fact_find_property_loan_ownersh_property_loan_id_contact_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_property_loan_ownership
    ADD CONSTRAINT fact_find_property_loan_ownersh_property_loan_id_contact_id_key UNIQUE (property_loan_id, entity_id);


--
-- Name: fact_find_property_loan_ownership fact_find_property_loan_ownership_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_property_loan_ownership
    ADD CONSTRAINT fact_find_property_loan_ownership_pkey PRIMARY KEY (id);


--
-- Name: fact_find_property_loan fact_find_property_loan_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_property_loan
    ADD CONSTRAINT fact_find_property_loan_pkey PRIMARY KEY (id);


--
-- Name: fact_find_retirement_asset_item fact_find_retirement_asset_item_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_retirement_asset_item
    ADD CONSTRAINT fact_find_retirement_asset_item_pkey PRIMARY KEY (id);


--
-- Name: fact_find_retirement_asset_ownership fact_find_retirement_asset_ow_retirement_asset_id_contact_i_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_retirement_asset_ownership
    ADD CONSTRAINT fact_find_retirement_asset_ow_retirement_asset_id_contact_i_key UNIQUE (retirement_asset_id, entity_id);


--
-- Name: fact_find_retirement_asset_ownership fact_find_retirement_asset_ownership_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_retirement_asset_ownership
    ADD CONSTRAINT fact_find_retirement_asset_ownership_pkey PRIMARY KEY (id);


--
-- Name: fact_find_retirement_asset fact_find_retirement_asset_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_retirement_asset
    ADD CONSTRAINT fact_find_retirement_asset_pkey PRIMARY KEY (id);


--
-- Name: fact_find_retirement_income_ownership fact_find_retirement_income_o_retirement_income_id_contact__key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_retirement_income_ownership
    ADD CONSTRAINT fact_find_retirement_income_o_retirement_income_id_contact__key UNIQUE (retirement_income_id, entity_id);


--
-- Name: fact_find_retirement_income_ownership fact_find_retirement_income_ownership_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_retirement_income_ownership
    ADD CONSTRAINT fact_find_retirement_income_ownership_pkey PRIMARY KEY (id);


--
-- Name: fact_find_retirement_income fact_find_retirement_income_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_retirement_income
    ADD CONSTRAINT fact_find_retirement_income_pkey PRIMARY KEY (id);


--
-- Name: fact_find_superannuation_item fact_find_superannuation_item_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_superannuation_item
    ADD CONSTRAINT fact_find_superannuation_item_pkey PRIMARY KEY (id);


--
-- Name: fact_find_superannuation_ownership fact_find_superannuation_owner_superannuation_id_contact_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_superannuation_ownership
    ADD CONSTRAINT fact_find_superannuation_owner_superannuation_id_contact_id_key UNIQUE (superannuation_id, entity_id);


--
-- Name: fact_find_superannuation_ownership fact_find_superannuation_ownership_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_superannuation_ownership
    ADD CONSTRAINT fact_find_superannuation_ownership_pkey PRIMARY KEY (id);


--
-- Name: fact_find_superannuation fact_find_superannuation_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_superannuation
    ADD CONSTRAINT fact_find_superannuation_pkey PRIMARY KEY (id);


--
-- Name: fact_find_vehicle_loan_ownership fact_find_vehicle_loan_ownership_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_vehicle_loan_ownership
    ADD CONSTRAINT fact_find_vehicle_loan_ownership_pkey PRIMARY KEY (id);


--
-- Name: fact_find_vehicle_loan_ownership fact_find_vehicle_loan_ownership_vehicle_loan_id_contact_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_vehicle_loan_ownership
    ADD CONSTRAINT fact_find_vehicle_loan_ownership_vehicle_loan_id_contact_id_key UNIQUE (vehicle_loan_id, entity_id);


--
-- Name: fact_find_vehicle_loan fact_find_vehicle_loan_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_vehicle_loan
    ADD CONSTRAINT fact_find_vehicle_loan_pkey PRIMARY KEY (id);


--
-- Name: fact_find_vehicle_ownership fact_find_vehicle_ownership_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_vehicle_ownership
    ADD CONSTRAINT fact_find_vehicle_ownership_pkey PRIMARY KEY (id);


--
-- Name: fact_find_vehicle_ownership fact_find_vehicle_ownership_vehicle_id_contact_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_vehicle_ownership
    ADD CONSTRAINT fact_find_vehicle_ownership_vehicle_id_contact_id_key UNIQUE (vehicle_id, entity_id);


--
-- Name: fact_find_vehicle fact_find_vehicle_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_vehicle
    ADD CONSTRAINT fact_find_vehicle_pkey PRIMARY KEY (id);


--
-- Name: financial_planner financial_planner_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.financial_planner
    ADD CONSTRAINT financial_planner_pkey PRIMARY KEY (id);


--
-- Name: financial_product_category financial_product_category_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.financial_product_category
    ADD CONSTRAINT financial_product_category_pkey PRIMARY KEY (code);


--
-- Name: financial_product financial_product_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.financial_product
    ADD CONSTRAINT financial_product_pkey PRIMARY KEY (id);


--
-- Name: goal goal_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.goal
    ADD CONSTRAINT goal_pkey PRIMARY KEY (id);


--
-- Name: investment_option investment_option_id_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.investment_option
    ADD CONSTRAINT investment_option_id_unique UNIQUE (investment_option_id);


--
-- Name: financial_product uk_rex_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.financial_product
    ADD CONSTRAINT uk_rex_id UNIQUE (rex_id);


--
-- Name: business_unit_code_unique; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX business_unit_code_unique ON public.business_unit USING btree (lower(TRIM(BOTH FROM code)));


--
-- Name: business_unit_parent_business_unit_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX business_unit_parent_business_unit_id_idx ON public.business_unit USING btree (parent_business_unit_id);


--
-- Name: case_entity_entity_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX case_entity_entity_id_idx ON public.case_entity USING btree (entity_id);


--
-- Name: case_financial_planner_financial_planner_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX case_financial_planner_financial_planner_id_idx ON public.case_financial_planner USING btree (financial_planner_id);


--
-- Name: case_one_primary_planner; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX case_one_primary_planner ON public.case_financial_planner USING btree (case_id) WHERE is_primary;


--
-- Name: cash_financial_product_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX cash_financial_product_idx ON public.fact_find_cash USING btree (financial_product_id);


--
-- Name: contact_email1_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX contact_email1_idx ON public.contact USING btree (email1);


--
-- Name: contact_financialPlannerId_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "contact_financialPlannerId_idx" ON public.contact USING btree ("financialPlannerId");


--
-- Name: contact_financialPlannerId_idx1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "contact_financialPlannerId_idx1" ON public.contact USING btree ("financialPlannerId");


--
-- Name: contact_lastName_firstName_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "contact_lastName_firstName_idx" ON public.contact USING btree ("lastName", "firstName");


--
-- Name: credit_card_financial_product_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX credit_card_financial_product_idx ON public.fact_find_credit_card USING btree (financial_product_id);


--
-- Name: crm_case_advice_type_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX crm_case_advice_type_idx ON public.crm_case USING btree (advice_type);


--
-- Name: crm_case_created_at_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX crm_case_created_at_idx ON public.crm_case USING btree (created_at DESC);


--
-- Name: crm_case_financial_planner_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX crm_case_financial_planner_idx ON public.crm_case USING btree (financial_planner);


--
-- Name: crm_note_case_id_created_at_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX crm_note_case_id_created_at_idx ON public.crm_note USING btree (case_id, created_at DESC);


--
-- Name: crm_note_entity_id_created_at_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX crm_note_entity_id_created_at_idx ON public.crm_note USING btree (entity_id, created_at DESC);


--
-- Name: crm_task_case_id_due_date_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX crm_task_case_id_due_date_idx ON public.crm_task USING btree (case_id, due_date);


--
-- Name: crm_task_entity_id_due_date_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX crm_task_entity_id_due_date_idx ON public.crm_task USING btree (entity_id, due_date);


--
-- Name: direct_investment_financial_product_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX direct_investment_financial_product_idx ON public.fact_find_direct_investment USING btree (financial_product_id);


--
-- Name: direct_investment_item_financial_product_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX direct_investment_item_financial_product_idx ON public.fact_find_direct_investment_item USING btree (financial_product_id);


--
-- Name: entity_financial_planner_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX entity_financial_planner_id_idx ON public.entity USING btree (financial_planner_id);


--
-- Name: entity_relationship_to_entity_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX entity_relationship_to_entity_id_idx ON public.entity_relationship USING btree (to_entity_id);


--
-- Name: fact_find_business_income_case_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_business_income_case_id_idx ON public.fact_find_business_income USING btree (case_id);


--
-- Name: fact_find_business_income_ownership_business_income_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_business_income_ownership_business_income_id_idx ON public.fact_find_business_income_ownership USING btree (business_income_id);


--
-- Name: fact_find_business_income_ownership_contact_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_business_income_ownership_contact_id_idx ON public.fact_find_business_income_ownership USING btree (entity_id);


--
-- Name: fact_find_cash_case_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_cash_case_id_idx ON public.fact_find_cash USING btree (case_id);


--
-- Name: fact_find_cash_ownership_contact_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_cash_ownership_contact_idx ON public.fact_find_cash_ownership USING btree (entity_id);


--
-- Name: fact_find_centrelink_income_case_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_centrelink_income_case_id_idx ON public.fact_find_centrelink_income USING btree (case_id);


--
-- Name: fact_find_centrelink_income_ownership_centrelink_income_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_centrelink_income_ownership_centrelink_income_id_idx ON public.fact_find_centrelink_income_ownership USING btree (centrelink_income_id);


--
-- Name: fact_find_centrelink_income_ownership_contact_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_centrelink_income_ownership_contact_id_idx ON public.fact_find_centrelink_income_ownership USING btree (entity_id);


--
-- Name: fact_find_credit_card_case_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_credit_card_case_id_idx ON public.fact_find_credit_card USING btree (case_id);


--
-- Name: fact_find_credit_card_ownership_contact_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_credit_card_ownership_contact_idx ON public.fact_find_credit_card_ownership USING btree (entity_id);


--
-- Name: fact_find_direct_investment_case_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_direct_investment_case_id_idx ON public.fact_find_direct_investment USING btree (case_id);


--
-- Name: fact_find_direct_investment_ownership_contact_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_direct_investment_ownership_contact_idx ON public.fact_find_direct_investment_ownership USING btree (entity_id);


--
-- Name: fact_find_expense_case_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_expense_case_id_idx ON public.fact_find_expense USING btree (case_id);


--
-- Name: fact_find_expense_ownership_contact_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_expense_ownership_contact_idx ON public.fact_find_expense_ownership USING btree (entity_id);


--
-- Name: fact_find_fixed_interest_case_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_fixed_interest_case_id_idx ON public.fact_find_fixed_interest USING btree (case_id);


--
-- Name: fact_find_fixed_interest_ownership_contact_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_fixed_interest_ownership_contact_idx ON public.fact_find_fixed_interest_ownership USING btree (entity_id);


--
-- Name: fact_find_foreign_income_case_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_foreign_income_case_id_idx ON public.fact_find_foreign_income USING btree (case_id);


--
-- Name: fact_find_foreign_income_ownership_contact_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_foreign_income_ownership_contact_id_idx ON public.fact_find_foreign_income_ownership USING btree (entity_id);


--
-- Name: fact_find_foreign_income_ownership_foreign_income_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_foreign_income_ownership_foreign_income_id_idx ON public.fact_find_foreign_income_ownership USING btree (foreign_income_id);


--
-- Name: fact_find_home_contents_case_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_home_contents_case_id_idx ON public.fact_find_home_contents USING btree (case_id);


--
-- Name: fact_find_home_contents_ownership_contact_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_home_contents_ownership_contact_idx ON public.fact_find_home_contents_ownership USING btree (entity_id);


--
-- Name: fact_find_insurance_policy_case_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_insurance_policy_case_id_idx ON public.fact_find_insurance_policy USING btree (case_id);


--
-- Name: fact_find_insurance_policy_ownership_contact_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_insurance_policy_ownership_contact_idx ON public.fact_find_insurance_policy_ownership USING btree (entity_id);


--
-- Name: fact_find_investment_income_case_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_investment_income_case_id_idx ON public.fact_find_investment_income USING btree (case_id);


--
-- Name: fact_find_investment_income_ownership_contact_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_investment_income_ownership_contact_id_idx ON public.fact_find_investment_income_ownership USING btree (entity_id);


--
-- Name: fact_find_investment_income_ownership_investment_income_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_investment_income_ownership_investment_income_id_idx ON public.fact_find_investment_income_ownership USING btree (investment_income_id);


--
-- Name: fact_find_investment_platform_case_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_investment_platform_case_id_idx ON public.fact_find_investment_platform USING btree (case_id);


--
-- Name: fact_find_investment_platform_ownership_contact_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_investment_platform_ownership_contact_idx ON public.fact_find_investment_platform_ownership USING btree (entity_id);


--
-- Name: fact_find_occupational_income_case_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_occupational_income_case_id_idx ON public.fact_find_occupational_income USING btree (case_id);


--
-- Name: fact_find_occupational_income_ownership_contact_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_occupational_income_ownership_contact_id_idx ON public.fact_find_occupational_income_ownership USING btree (entity_id);


--
-- Name: fact_find_occupational_income_ownership_occupational_i_72e472bf; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_occupational_income_ownership_occupational_i_72e472bf ON public.fact_find_occupational_income_ownership USING btree (occupational_income_id);


--
-- Name: fact_find_other_asset_case_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_other_asset_case_id_idx ON public.fact_find_other_asset USING btree (case_id);


--
-- Name: fact_find_other_asset_ownership_contact_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_other_asset_ownership_contact_idx ON public.fact_find_other_asset_ownership USING btree (entity_id);


--
-- Name: fact_find_other_income_case_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_other_income_case_id_idx ON public.fact_find_other_income USING btree (case_id);


--
-- Name: fact_find_other_income_ownership_contact_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_other_income_ownership_contact_id_idx ON public.fact_find_other_income_ownership USING btree (entity_id);


--
-- Name: fact_find_other_income_ownership_other_income_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_other_income_ownership_other_income_id_idx ON public.fact_find_other_income_ownership USING btree (other_income_id);


--
-- Name: fact_find_other_liability_case_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_other_liability_case_id_idx ON public.fact_find_other_liability USING btree (case_id);


--
-- Name: fact_find_other_liability_ownership_contact_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_other_liability_ownership_contact_idx ON public.fact_find_other_liability_ownership USING btree (entity_id);


--
-- Name: fact_find_personal_loan_case_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_personal_loan_case_id_idx ON public.fact_find_personal_loan USING btree (case_id);


--
-- Name: fact_find_personal_loan_ownership_contact_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_personal_loan_ownership_contact_idx ON public.fact_find_personal_loan_ownership USING btree (entity_id);


--
-- Name: fact_find_principal_residence_case_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_principal_residence_case_id_idx ON public.fact_find_principal_residence USING btree (case_id);


--
-- Name: fact_find_principal_residence_ownership_contact_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_principal_residence_ownership_contact_idx ON public.fact_find_principal_residence_ownership USING btree (entity_id);


--
-- Name: fact_find_property_asset_case_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_property_asset_case_id_idx ON public.fact_find_property_asset USING btree (case_id);


--
-- Name: fact_find_property_asset_ownership_contact_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_property_asset_ownership_contact_idx ON public.fact_find_property_asset_ownership USING btree (entity_id);


--
-- Name: fact_find_property_income_case_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_property_income_case_id_idx ON public.fact_find_property_income USING btree (case_id);


--
-- Name: fact_find_property_income_ownership_contact_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_property_income_ownership_contact_id_idx ON public.fact_find_property_income_ownership USING btree (entity_id);


--
-- Name: fact_find_property_income_ownership_property_income_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_property_income_ownership_property_income_id_idx ON public.fact_find_property_income_ownership USING btree (property_income_id);


--
-- Name: fact_find_property_loan_case_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_property_loan_case_id_idx ON public.fact_find_property_loan USING btree (case_id);


--
-- Name: fact_find_property_loan_ownership_contact_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_property_loan_ownership_contact_idx ON public.fact_find_property_loan_ownership USING btree (entity_id);


--
-- Name: fact_find_retirement_asset_case_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_retirement_asset_case_id_idx ON public.fact_find_retirement_asset USING btree (case_id);


--
-- Name: fact_find_retirement_asset_ownership_contact_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_retirement_asset_ownership_contact_idx ON public.fact_find_retirement_asset_ownership USING btree (entity_id);


--
-- Name: fact_find_retirement_income_case_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_retirement_income_case_id_idx ON public.fact_find_retirement_income USING btree (case_id);


--
-- Name: fact_find_retirement_income_ownership_contact_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_retirement_income_ownership_contact_id_idx ON public.fact_find_retirement_income_ownership USING btree (entity_id);


--
-- Name: fact_find_retirement_income_ownership_retirement_income_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_retirement_income_ownership_retirement_income_id_idx ON public.fact_find_retirement_income_ownership USING btree (retirement_income_id);


--
-- Name: fact_find_superannuation_case_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_superannuation_case_id_idx ON public.fact_find_superannuation USING btree (case_id);


--
-- Name: fact_find_superannuation_ownership_contact_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_superannuation_ownership_contact_idx ON public.fact_find_superannuation_ownership USING btree (entity_id);


--
-- Name: fact_find_vehicle_case_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_vehicle_case_id_idx ON public.fact_find_vehicle USING btree (case_id);


--
-- Name: fact_find_vehicle_loan_case_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_vehicle_loan_case_id_idx ON public.fact_find_vehicle_loan USING btree (case_id);


--
-- Name: fact_find_vehicle_loan_ownership_contact_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_vehicle_loan_ownership_contact_idx ON public.fact_find_vehicle_loan_ownership USING btree (entity_id);


--
-- Name: fact_find_vehicle_ownership_contact_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fact_find_vehicle_ownership_contact_idx ON public.fact_find_vehicle_ownership USING btree (entity_id);


--
-- Name: financial_planner_business_unit_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX financial_planner_business_unit_id_idx ON public.financial_planner USING btree (business_unit_id);


--
-- Name: financial_planner_is_active_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX financial_planner_is_active_idx ON public.financial_planner USING btree (is_active);


--
-- Name: financial_product_category_active_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX financial_product_category_active_idx ON public.financial_product USING btree (product_category, is_active);


--
-- Name: financial_product_external_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX financial_product_external_idx ON public.financial_product USING btree (source, external_id) WHERE (external_id IS NOT NULL);


--
-- Name: financial_product_provider_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX financial_product_provider_idx ON public.financial_product USING btree (provider_name);


--
-- Name: fixed_interest_financial_product_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fixed_interest_financial_product_idx ON public.fact_find_fixed_interest USING btree (financial_product_id);


--
-- Name: goal_case_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX goal_case_id_idx ON public.goal USING btree (case_id);


--
-- Name: insurance_policy_financial_product_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX insurance_policy_financial_product_idx ON public.fact_find_insurance_policy USING btree (financial_product_id);


--
-- Name: investment_holding_option_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX investment_holding_option_idx ON public.fact_find_investment_holding USING btree (investment_option_id);


--
-- Name: investment_option_product_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX investment_option_product_idx ON public.investment_option USING btree (linked_product);


--
-- Name: investment_platform_financial_product_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX investment_platform_financial_product_idx ON public.fact_find_investment_platform USING btree (financial_product_id);


--
-- Name: investment_platform_item_financial_product_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX investment_platform_item_financial_product_idx ON public.fact_find_investment_platform_item USING btree (financial_product_id);


--
-- Name: personal_loan_financial_product_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX personal_loan_financial_product_idx ON public.fact_find_personal_loan USING btree (financial_product_id);


--
-- Name: property_loan_financial_product_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX property_loan_financial_product_idx ON public.fact_find_property_loan USING btree (financial_product_id);


--
-- Name: retirement_asset_financial_product_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX retirement_asset_financial_product_idx ON public.fact_find_retirement_asset USING btree (financial_product_id);


--
-- Name: retirement_asset_item_financial_product_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX retirement_asset_item_financial_product_idx ON public.fact_find_retirement_asset_item USING btree (financial_product_id);


--
-- Name: superannuation_financial_product_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX superannuation_financial_product_idx ON public.fact_find_superannuation USING btree (financial_product_id);


--
-- Name: superannuation_item_financial_product_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX superannuation_item_financial_product_idx ON public.fact_find_superannuation_item USING btree (financial_product_id);


--
-- Name: vehicle_loan_financial_product_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX vehicle_loan_financial_product_idx ON public.fact_find_vehicle_loan USING btree (financial_product_id);


--
-- Name: contact contact_entity_sync; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER contact_entity_sync BEFORE INSERT OR UPDATE ON public.contact FOR EACH ROW EXECUTE FUNCTION public.sync_contact_entity();


--
-- Name: contact contact_updatedAt_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "contact_updatedAt_trigger" BEFORE UPDATE ON public.contact FOR EACH ROW EXECUTE FUNCTION public."contact_set_updatedAt"();


--
-- Name: entity entity_contact_type_check; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER entity_contact_type_check BEFORE UPDATE OF entity_type ON public.entity FOR EACH ROW EXECUTE FUNCTION public.protect_contact_entity_type();


--
-- Name: fact_find_investment_platform investment_account_balance; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER investment_account_balance BEFORE INSERT OR UPDATE ON public.fact_find_investment_platform FOR EACH ROW EXECUTE FUNCTION public.investment_account_balance();


--
-- Name: fact_find_retirement_asset investment_account_balance; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER investment_account_balance BEFORE INSERT OR UPDATE ON public.fact_find_retirement_asset FOR EACH ROW EXECUTE FUNCTION public.investment_account_balance();


--
-- Name: fact_find_superannuation investment_account_balance; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER investment_account_balance BEFORE INSERT OR UPDATE ON public.fact_find_superannuation FOR EACH ROW EXECUTE FUNCTION public.investment_account_balance();


--
-- Name: fact_find_investment_holding investment_holding_revalue; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER investment_holding_revalue AFTER INSERT OR DELETE OR UPDATE ON public.fact_find_investment_holding FOR EACH ROW EXECUTE FUNCTION public.investment_holding_revalue();


--
-- Name: fact_find_investment_holding investment_holding_validate; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER investment_holding_validate BEFORE INSERT OR UPDATE ON public.fact_find_investment_holding FOR EACH ROW EXECUTE FUNCTION public.investment_holding_validate();


--
-- Name: investment_option investment_option_revalue; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER investment_option_revalue AFTER UPDATE OF current_price, linked_product ON public.investment_option FOR EACH ROW EXECUTE FUNCTION public.investment_option_revalue();


--
-- Name: financial_product investment_product_revalidate; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER investment_product_revalidate AFTER UPDATE OF rex_id ON public.financial_product FOR EACH ROW EXECUTE FUNCTION public.investment_product_revalidate();


--
-- Name: business_unit business_unit_parent_business_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.business_unit
    ADD CONSTRAINT business_unit_parent_business_unit_id_fkey FOREIGN KEY (parent_business_unit_id) REFERENCES public.business_unit(id) ON DELETE RESTRICT;


--
-- Name: case_entity case_entity_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.case_entity
    ADD CONSTRAINT case_entity_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: case_entity case_entity_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.case_entity
    ADD CONSTRAINT case_entity_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: case_financial_planner case_financial_planner_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.case_financial_planner
    ADD CONSTRAINT case_financial_planner_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: case_financial_planner case_financial_planner_financial_planner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.case_financial_planner
    ADD CONSTRAINT case_financial_planner_financial_planner_id_fkey FOREIGN KEY (financial_planner_id) REFERENCES public.financial_planner(id) ON DELETE RESTRICT;


--
-- Name: contact contact_business_unit_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contact
    ADD CONSTRAINT contact_business_unit_fk FOREIGN KEY ("businessUnitId") REFERENCES public.business_unit(id) ON DELETE RESTRICT;


--
-- Name: contact contact_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contact
    ADD CONSTRAINT contact_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: contact contact_planner_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contact
    ADD CONSTRAINT contact_planner_fk FOREIGN KEY ("financialPlannerId") REFERENCES public.financial_planner(id) ON DELETE RESTRICT;


--
-- Name: crm_note crm_note_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.crm_note
    ADD CONSTRAINT crm_note_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: crm_note crm_note_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.crm_note
    ADD CONSTRAINT crm_note_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: crm_task crm_task_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.crm_task
    ADD CONSTRAINT crm_task_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: crm_task crm_task_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.crm_task
    ADD CONSTRAINT crm_task_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: entity entity_financial_planner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.entity
    ADD CONSTRAINT entity_financial_planner_id_fkey FOREIGN KEY (financial_planner_id) REFERENCES public.financial_planner(id) ON DELETE RESTRICT;


--
-- Name: entity_relationship entity_relationship_from_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.entity_relationship
    ADD CONSTRAINT entity_relationship_from_entity_id_fkey FOREIGN KEY (from_entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: entity_relationship entity_relationship_to_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.entity_relationship
    ADD CONSTRAINT entity_relationship_to_entity_id_fkey FOREIGN KEY (to_entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: fact_find_beneficiary fact_find_beneficiary_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_beneficiary
    ADD CONSTRAINT fact_find_beneficiary_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contact(id) ON DELETE SET NULL;


--
-- Name: fact_find_beneficiary fact_find_beneficiary_insurance_policy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_beneficiary
    ADD CONSTRAINT fact_find_beneficiary_insurance_policy_id_fkey FOREIGN KEY (insurance_policy_id) REFERENCES public.fact_find_insurance_policy(id) ON DELETE CASCADE;


--
-- Name: fact_find_beneficiary fact_find_beneficiary_retirement_asset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_beneficiary
    ADD CONSTRAINT fact_find_beneficiary_retirement_asset_id_fkey FOREIGN KEY (retirement_asset_id) REFERENCES public.fact_find_retirement_asset(id) ON DELETE CASCADE;


--
-- Name: fact_find_beneficiary fact_find_beneficiary_superannuation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_beneficiary
    ADD CONSTRAINT fact_find_beneficiary_superannuation_id_fkey FOREIGN KEY (superannuation_id) REFERENCES public.fact_find_superannuation(id) ON DELETE CASCADE;


--
-- Name: fact_find_business_income fact_find_business_income_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_business_income
    ADD CONSTRAINT fact_find_business_income_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: fact_find_business_income_ownership fact_find_business_income_ownership_business_income_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_business_income_ownership
    ADD CONSTRAINT fact_find_business_income_ownership_business_income_id_fkey FOREIGN KEY (business_income_id) REFERENCES public.fact_find_business_income(id) ON DELETE CASCADE;


--
-- Name: fact_find_business_income_ownership fact_find_business_income_ownership_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_business_income_ownership
    ADD CONSTRAINT fact_find_business_income_ownership_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: fact_find_cash fact_find_cash_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_cash
    ADD CONSTRAINT fact_find_cash_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: fact_find_cash fact_find_cash_financial_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_cash
    ADD CONSTRAINT fact_find_cash_financial_product_id_fkey FOREIGN KEY (financial_product_id) REFERENCES public.financial_product(id) ON DELETE RESTRICT;


--
-- Name: fact_find_cash_ownership fact_find_cash_ownership_cash_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_cash_ownership
    ADD CONSTRAINT fact_find_cash_ownership_cash_id_fkey FOREIGN KEY (cash_id) REFERENCES public.fact_find_cash(id) ON DELETE CASCADE;


--
-- Name: fact_find_cash_ownership fact_find_cash_ownership_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_cash_ownership
    ADD CONSTRAINT fact_find_cash_ownership_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: fact_find_centrelink_income fact_find_centrelink_income_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_centrelink_income
    ADD CONSTRAINT fact_find_centrelink_income_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: fact_find_centrelink_income_ownership fact_find_centrelink_income_ownership_centrelink_income_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_centrelink_income_ownership
    ADD CONSTRAINT fact_find_centrelink_income_ownership_centrelink_income_id_fkey FOREIGN KEY (centrelink_income_id) REFERENCES public.fact_find_centrelink_income(id) ON DELETE CASCADE;


--
-- Name: fact_find_centrelink_income_ownership fact_find_centrelink_income_ownership_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_centrelink_income_ownership
    ADD CONSTRAINT fact_find_centrelink_income_ownership_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: fact_find_credit_card fact_find_credit_card_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_credit_card
    ADD CONSTRAINT fact_find_credit_card_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: fact_find_credit_card fact_find_credit_card_financial_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_credit_card
    ADD CONSTRAINT fact_find_credit_card_financial_product_id_fkey FOREIGN KEY (financial_product_id) REFERENCES public.financial_product(id) ON DELETE RESTRICT;


--
-- Name: fact_find_credit_card_ownership fact_find_credit_card_ownership_credit_card_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_credit_card_ownership
    ADD CONSTRAINT fact_find_credit_card_ownership_credit_card_id_fkey FOREIGN KEY (credit_card_id) REFERENCES public.fact_find_credit_card(id) ON DELETE CASCADE;


--
-- Name: fact_find_credit_card_ownership fact_find_credit_card_ownership_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_credit_card_ownership
    ADD CONSTRAINT fact_find_credit_card_ownership_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: fact_find_direct_investment fact_find_direct_investment_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_direct_investment
    ADD CONSTRAINT fact_find_direct_investment_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: fact_find_direct_investment fact_find_direct_investment_financial_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_direct_investment
    ADD CONSTRAINT fact_find_direct_investment_financial_product_id_fkey FOREIGN KEY (financial_product_id) REFERENCES public.financial_product(id) ON DELETE RESTRICT;


--
-- Name: fact_find_direct_investment_item fact_find_direct_investment_item_direct_investment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_direct_investment_item
    ADD CONSTRAINT fact_find_direct_investment_item_direct_investment_id_fkey FOREIGN KEY (direct_investment_id) REFERENCES public.fact_find_direct_investment(id) ON DELETE CASCADE;


--
-- Name: fact_find_direct_investment_item fact_find_direct_investment_item_financial_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_direct_investment_item
    ADD CONSTRAINT fact_find_direct_investment_item_financial_product_id_fkey FOREIGN KEY (financial_product_id) REFERENCES public.financial_product(id) ON DELETE RESTRICT;


--
-- Name: fact_find_direct_investment_ownership fact_find_direct_investment_ownership_direct_investment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_direct_investment_ownership
    ADD CONSTRAINT fact_find_direct_investment_ownership_direct_investment_id_fkey FOREIGN KEY (direct_investment_id) REFERENCES public.fact_find_direct_investment(id) ON DELETE CASCADE;


--
-- Name: fact_find_direct_investment_ownership fact_find_direct_investment_ownership_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_direct_investment_ownership
    ADD CONSTRAINT fact_find_direct_investment_ownership_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: fact_find_expense fact_find_expense_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_expense
    ADD CONSTRAINT fact_find_expense_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: fact_find_expense_ownership fact_find_expense_ownership_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_expense_ownership
    ADD CONSTRAINT fact_find_expense_ownership_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: fact_find_expense_ownership fact_find_expense_ownership_expense_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_expense_ownership
    ADD CONSTRAINT fact_find_expense_ownership_expense_id_fkey FOREIGN KEY (expense_id) REFERENCES public.fact_find_expense(id) ON DELETE CASCADE;


--
-- Name: fact_find_fixed_interest fact_find_fixed_interest_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_fixed_interest
    ADD CONSTRAINT fact_find_fixed_interest_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: fact_find_fixed_interest fact_find_fixed_interest_financial_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_fixed_interest
    ADD CONSTRAINT fact_find_fixed_interest_financial_product_id_fkey FOREIGN KEY (financial_product_id) REFERENCES public.financial_product(id) ON DELETE RESTRICT;


--
-- Name: fact_find_fixed_interest_ownership fact_find_fixed_interest_ownership_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_fixed_interest_ownership
    ADD CONSTRAINT fact_find_fixed_interest_ownership_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: fact_find_fixed_interest_ownership fact_find_fixed_interest_ownership_fixed_interest_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_fixed_interest_ownership
    ADD CONSTRAINT fact_find_fixed_interest_ownership_fixed_interest_id_fkey FOREIGN KEY (fixed_interest_id) REFERENCES public.fact_find_fixed_interest(id) ON DELETE CASCADE;


--
-- Name: fact_find_foreign_income fact_find_foreign_income_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_foreign_income
    ADD CONSTRAINT fact_find_foreign_income_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: fact_find_foreign_income_ownership fact_find_foreign_income_ownership_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_foreign_income_ownership
    ADD CONSTRAINT fact_find_foreign_income_ownership_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: fact_find_foreign_income_ownership fact_find_foreign_income_ownership_foreign_income_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_foreign_income_ownership
    ADD CONSTRAINT fact_find_foreign_income_ownership_foreign_income_id_fkey FOREIGN KEY (foreign_income_id) REFERENCES public.fact_find_foreign_income(id) ON DELETE CASCADE;


--
-- Name: fact_find_home_contents fact_find_home_contents_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_home_contents
    ADD CONSTRAINT fact_find_home_contents_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: fact_find_home_contents_ownership fact_find_home_contents_ownership_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_home_contents_ownership
    ADD CONSTRAINT fact_find_home_contents_ownership_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: fact_find_home_contents_ownership fact_find_home_contents_ownership_home_contents_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_home_contents_ownership
    ADD CONSTRAINT fact_find_home_contents_ownership_home_contents_id_fkey FOREIGN KEY (home_contents_id) REFERENCES public.fact_find_home_contents(id) ON DELETE CASCADE;


--
-- Name: fact_find_insurance_policy fact_find_insurance_policy_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_insurance_policy
    ADD CONSTRAINT fact_find_insurance_policy_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: fact_find_insurance_policy_feature fact_find_insurance_policy_feature_insurance_policy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_insurance_policy_feature
    ADD CONSTRAINT fact_find_insurance_policy_feature_insurance_policy_id_fkey FOREIGN KEY (insurance_policy_id) REFERENCES public.fact_find_insurance_policy(id) ON DELETE CASCADE;


--
-- Name: fact_find_insurance_policy fact_find_insurance_policy_financial_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_insurance_policy
    ADD CONSTRAINT fact_find_insurance_policy_financial_product_id_fkey FOREIGN KEY (financial_product_id) REFERENCES public.financial_product(id) ON DELETE RESTRICT;


--
-- Name: fact_find_insurance_policy_item fact_find_insurance_policy_item_insurance_policy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_insurance_policy_item
    ADD CONSTRAINT fact_find_insurance_policy_item_insurance_policy_id_fkey FOREIGN KEY (insurance_policy_id) REFERENCES public.fact_find_insurance_policy(id) ON DELETE CASCADE;


--
-- Name: fact_find_insurance_policy_ownership fact_find_insurance_policy_ownership_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_insurance_policy_ownership
    ADD CONSTRAINT fact_find_insurance_policy_ownership_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: fact_find_insurance_policy_ownership fact_find_insurance_policy_ownership_insurance_policy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_insurance_policy_ownership
    ADD CONSTRAINT fact_find_insurance_policy_ownership_insurance_policy_id_fkey FOREIGN KEY (insurance_policy_id) REFERENCES public.fact_find_insurance_policy(id) ON DELETE CASCADE;


--
-- Name: fact_find_investment_holding fact_find_investment_holding_investment_option_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_investment_holding
    ADD CONSTRAINT fact_find_investment_holding_investment_option_id_fkey FOREIGN KEY (investment_option_id) REFERENCES public.investment_option(investment_option_id) ON DELETE RESTRICT;


--
-- Name: fact_find_investment_holding fact_find_investment_holding_investment_platform_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_investment_holding
    ADD CONSTRAINT fact_find_investment_holding_investment_platform_id_fkey FOREIGN KEY (investment_platform_id) REFERENCES public.fact_find_investment_platform(id) ON DELETE CASCADE;


--
-- Name: fact_find_investment_holding fact_find_investment_holding_retirement_asset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_investment_holding
    ADD CONSTRAINT fact_find_investment_holding_retirement_asset_id_fkey FOREIGN KEY (retirement_asset_id) REFERENCES public.fact_find_retirement_asset(id) ON DELETE CASCADE;


--
-- Name: fact_find_investment_holding fact_find_investment_holding_superannuation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_investment_holding
    ADD CONSTRAINT fact_find_investment_holding_superannuation_id_fkey FOREIGN KEY (superannuation_id) REFERENCES public.fact_find_superannuation(id) ON DELETE CASCADE;


--
-- Name: fact_find_investment_income fact_find_investment_income_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_investment_income
    ADD CONSTRAINT fact_find_investment_income_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: fact_find_investment_income_ownership fact_find_investment_income_ownership_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_investment_income_ownership
    ADD CONSTRAINT fact_find_investment_income_ownership_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: fact_find_investment_income_ownership fact_find_investment_income_ownership_investment_income_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_investment_income_ownership
    ADD CONSTRAINT fact_find_investment_income_ownership_investment_income_id_fkey FOREIGN KEY (investment_income_id) REFERENCES public.fact_find_investment_income(id) ON DELETE CASCADE;


--
-- Name: fact_find_investment_platform fact_find_investment_platform_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_investment_platform
    ADD CONSTRAINT fact_find_investment_platform_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: fact_find_investment_platform fact_find_investment_platform_financial_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_investment_platform
    ADD CONSTRAINT fact_find_investment_platform_financial_product_id_fkey FOREIGN KEY (financial_product_id) REFERENCES public.financial_product(id) ON DELETE RESTRICT;


--
-- Name: fact_find_investment_platform_item fact_find_investment_platform_item_financial_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_investment_platform_item
    ADD CONSTRAINT fact_find_investment_platform_item_financial_product_id_fkey FOREIGN KEY (financial_product_id) REFERENCES public.financial_product(id) ON DELETE RESTRICT;


--
-- Name: fact_find_investment_platform_item fact_find_investment_platform_item_investment_platform_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_investment_platform_item
    ADD CONSTRAINT fact_find_investment_platform_item_investment_platform_id_fkey FOREIGN KEY (investment_platform_id) REFERENCES public.fact_find_investment_platform(id) ON DELETE CASCADE;


--
-- Name: fact_find_investment_platform_ownership fact_find_investment_platform_owner_investment_platform_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_investment_platform_ownership
    ADD CONSTRAINT fact_find_investment_platform_owner_investment_platform_id_fkey FOREIGN KEY (investment_platform_id) REFERENCES public.fact_find_investment_platform(id) ON DELETE CASCADE;


--
-- Name: fact_find_investment_platform_ownership fact_find_investment_platform_ownership_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_investment_platform_ownership
    ADD CONSTRAINT fact_find_investment_platform_ownership_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: fact_find_occupational_income fact_find_occupational_income_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_occupational_income
    ADD CONSTRAINT fact_find_occupational_income_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: fact_find_occupational_income_ownership fact_find_occupational_income_ownership_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_occupational_income_ownership
    ADD CONSTRAINT fact_find_occupational_income_ownership_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: fact_find_occupational_income_ownership fact_find_occupational_income_ownership_occupational_i_bfe02827; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_occupational_income_ownership
    ADD CONSTRAINT fact_find_occupational_income_ownership_occupational_i_bfe02827 FOREIGN KEY (occupational_income_id) REFERENCES public.fact_find_occupational_income(id) ON DELETE CASCADE;


--
-- Name: fact_find_other_asset fact_find_other_asset_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_other_asset
    ADD CONSTRAINT fact_find_other_asset_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: fact_find_other_asset_ownership fact_find_other_asset_ownership_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_other_asset_ownership
    ADD CONSTRAINT fact_find_other_asset_ownership_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: fact_find_other_asset_ownership fact_find_other_asset_ownership_other_asset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_other_asset_ownership
    ADD CONSTRAINT fact_find_other_asset_ownership_other_asset_id_fkey FOREIGN KEY (other_asset_id) REFERENCES public.fact_find_other_asset(id) ON DELETE CASCADE;


--
-- Name: fact_find_other_income fact_find_other_income_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_other_income
    ADD CONSTRAINT fact_find_other_income_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: fact_find_other_income_ownership fact_find_other_income_ownership_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_other_income_ownership
    ADD CONSTRAINT fact_find_other_income_ownership_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: fact_find_other_income_ownership fact_find_other_income_ownership_other_income_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_other_income_ownership
    ADD CONSTRAINT fact_find_other_income_ownership_other_income_id_fkey FOREIGN KEY (other_income_id) REFERENCES public.fact_find_other_income(id) ON DELETE CASCADE;


--
-- Name: fact_find_other_liability fact_find_other_liability_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_other_liability
    ADD CONSTRAINT fact_find_other_liability_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: fact_find_other_liability_ownership fact_find_other_liability_ownership_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_other_liability_ownership
    ADD CONSTRAINT fact_find_other_liability_ownership_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: fact_find_other_liability_ownership fact_find_other_liability_ownership_other_liability_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_other_liability_ownership
    ADD CONSTRAINT fact_find_other_liability_ownership_other_liability_id_fkey FOREIGN KEY (other_liability_id) REFERENCES public.fact_find_other_liability(id) ON DELETE CASCADE;


--
-- Name: fact_find_personal_loan fact_find_personal_loan_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_personal_loan
    ADD CONSTRAINT fact_find_personal_loan_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: fact_find_personal_loan fact_find_personal_loan_financial_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_personal_loan
    ADD CONSTRAINT fact_find_personal_loan_financial_product_id_fkey FOREIGN KEY (financial_product_id) REFERENCES public.financial_product(id) ON DELETE RESTRICT;


--
-- Name: fact_find_personal_loan_ownership fact_find_personal_loan_ownership_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_personal_loan_ownership
    ADD CONSTRAINT fact_find_personal_loan_ownership_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: fact_find_personal_loan_ownership fact_find_personal_loan_ownership_personal_loan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_personal_loan_ownership
    ADD CONSTRAINT fact_find_personal_loan_ownership_personal_loan_id_fkey FOREIGN KEY (personal_loan_id) REFERENCES public.fact_find_personal_loan(id) ON DELETE CASCADE;


--
-- Name: fact_find_principal_residence fact_find_principal_residence_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_principal_residence
    ADD CONSTRAINT fact_find_principal_residence_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: fact_find_principal_residence_ownership fact_find_principal_residence_owner_principal_residence_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_principal_residence_ownership
    ADD CONSTRAINT fact_find_principal_residence_owner_principal_residence_id_fkey FOREIGN KEY (principal_residence_id) REFERENCES public.fact_find_principal_residence(id) ON DELETE CASCADE;


--
-- Name: fact_find_principal_residence_ownership fact_find_principal_residence_ownership_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_principal_residence_ownership
    ADD CONSTRAINT fact_find_principal_residence_ownership_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: fact_find_property_asset fact_find_property_asset_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_property_asset
    ADD CONSTRAINT fact_find_property_asset_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: fact_find_property_asset_ownership fact_find_property_asset_ownership_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_property_asset_ownership
    ADD CONSTRAINT fact_find_property_asset_ownership_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: fact_find_property_asset_ownership fact_find_property_asset_ownership_property_asset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_property_asset_ownership
    ADD CONSTRAINT fact_find_property_asset_ownership_property_asset_id_fkey FOREIGN KEY (property_asset_id) REFERENCES public.fact_find_property_asset(id) ON DELETE CASCADE;


--
-- Name: fact_find_property_income fact_find_property_income_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_property_income
    ADD CONSTRAINT fact_find_property_income_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: fact_find_property_income_ownership fact_find_property_income_ownership_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_property_income_ownership
    ADD CONSTRAINT fact_find_property_income_ownership_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: fact_find_property_income_ownership fact_find_property_income_ownership_property_income_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_property_income_ownership
    ADD CONSTRAINT fact_find_property_income_ownership_property_income_id_fkey FOREIGN KEY (property_income_id) REFERENCES public.fact_find_property_income(id) ON DELETE CASCADE;


--
-- Name: fact_find_property_loan fact_find_property_loan_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_property_loan
    ADD CONSTRAINT fact_find_property_loan_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: fact_find_property_loan fact_find_property_loan_financial_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_property_loan
    ADD CONSTRAINT fact_find_property_loan_financial_product_id_fkey FOREIGN KEY (financial_product_id) REFERENCES public.financial_product(id) ON DELETE RESTRICT;


--
-- Name: fact_find_property_loan_ownership fact_find_property_loan_ownership_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_property_loan_ownership
    ADD CONSTRAINT fact_find_property_loan_ownership_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: fact_find_property_loan_ownership fact_find_property_loan_ownership_property_loan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_property_loan_ownership
    ADD CONSTRAINT fact_find_property_loan_ownership_property_loan_id_fkey FOREIGN KEY (property_loan_id) REFERENCES public.fact_find_property_loan(id) ON DELETE CASCADE;


--
-- Name: fact_find_retirement_asset fact_find_retirement_asset_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_retirement_asset
    ADD CONSTRAINT fact_find_retirement_asset_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: fact_find_retirement_asset fact_find_retirement_asset_financial_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_retirement_asset
    ADD CONSTRAINT fact_find_retirement_asset_financial_product_id_fkey FOREIGN KEY (financial_product_id) REFERENCES public.financial_product(id) ON DELETE RESTRICT;


--
-- Name: fact_find_retirement_asset_item fact_find_retirement_asset_item_financial_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_retirement_asset_item
    ADD CONSTRAINT fact_find_retirement_asset_item_financial_product_id_fkey FOREIGN KEY (financial_product_id) REFERENCES public.financial_product(id) ON DELETE RESTRICT;


--
-- Name: fact_find_retirement_asset_item fact_find_retirement_asset_item_retirement_asset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_retirement_asset_item
    ADD CONSTRAINT fact_find_retirement_asset_item_retirement_asset_id_fkey FOREIGN KEY (retirement_asset_id) REFERENCES public.fact_find_retirement_asset(id) ON DELETE CASCADE;


--
-- Name: fact_find_retirement_asset_ownership fact_find_retirement_asset_ownership_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_retirement_asset_ownership
    ADD CONSTRAINT fact_find_retirement_asset_ownership_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: fact_find_retirement_asset_ownership fact_find_retirement_asset_ownership_retirement_asset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_retirement_asset_ownership
    ADD CONSTRAINT fact_find_retirement_asset_ownership_retirement_asset_id_fkey FOREIGN KEY (retirement_asset_id) REFERENCES public.fact_find_retirement_asset(id) ON DELETE CASCADE;


--
-- Name: fact_find_retirement_income fact_find_retirement_income_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_retirement_income
    ADD CONSTRAINT fact_find_retirement_income_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: fact_find_retirement_income_ownership fact_find_retirement_income_ownership_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_retirement_income_ownership
    ADD CONSTRAINT fact_find_retirement_income_ownership_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: fact_find_retirement_income_ownership fact_find_retirement_income_ownership_retirement_income_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_retirement_income_ownership
    ADD CONSTRAINT fact_find_retirement_income_ownership_retirement_income_id_fkey FOREIGN KEY (retirement_income_id) REFERENCES public.fact_find_retirement_income(id) ON DELETE CASCADE;


--
-- Name: fact_find_superannuation fact_find_superannuation_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_superannuation
    ADD CONSTRAINT fact_find_superannuation_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: fact_find_superannuation fact_find_superannuation_financial_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_superannuation
    ADD CONSTRAINT fact_find_superannuation_financial_product_id_fkey FOREIGN KEY (financial_product_id) REFERENCES public.financial_product(id) ON DELETE RESTRICT;


--
-- Name: fact_find_superannuation_item fact_find_superannuation_item_financial_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_superannuation_item
    ADD CONSTRAINT fact_find_superannuation_item_financial_product_id_fkey FOREIGN KEY (financial_product_id) REFERENCES public.financial_product(id) ON DELETE RESTRICT;


--
-- Name: fact_find_superannuation_item fact_find_superannuation_item_superannuation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_superannuation_item
    ADD CONSTRAINT fact_find_superannuation_item_superannuation_id_fkey FOREIGN KEY (superannuation_id) REFERENCES public.fact_find_superannuation(id) ON DELETE CASCADE;


--
-- Name: fact_find_superannuation_ownership fact_find_superannuation_ownership_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_superannuation_ownership
    ADD CONSTRAINT fact_find_superannuation_ownership_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: fact_find_superannuation_ownership fact_find_superannuation_ownership_superannuation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_superannuation_ownership
    ADD CONSTRAINT fact_find_superannuation_ownership_superannuation_id_fkey FOREIGN KEY (superannuation_id) REFERENCES public.fact_find_superannuation(id) ON DELETE CASCADE;


--
-- Name: fact_find_vehicle fact_find_vehicle_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_vehicle
    ADD CONSTRAINT fact_find_vehicle_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: fact_find_vehicle_loan fact_find_vehicle_loan_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_vehicle_loan
    ADD CONSTRAINT fact_find_vehicle_loan_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: fact_find_vehicle_loan fact_find_vehicle_loan_financial_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_vehicle_loan
    ADD CONSTRAINT fact_find_vehicle_loan_financial_product_id_fkey FOREIGN KEY (financial_product_id) REFERENCES public.financial_product(id) ON DELETE RESTRICT;


--
-- Name: fact_find_vehicle_loan_ownership fact_find_vehicle_loan_ownership_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_vehicle_loan_ownership
    ADD CONSTRAINT fact_find_vehicle_loan_ownership_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: fact_find_vehicle_loan_ownership fact_find_vehicle_loan_ownership_vehicle_loan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_vehicle_loan_ownership
    ADD CONSTRAINT fact_find_vehicle_loan_ownership_vehicle_loan_id_fkey FOREIGN KEY (vehicle_loan_id) REFERENCES public.fact_find_vehicle_loan(id) ON DELETE CASCADE;


--
-- Name: fact_find_vehicle_ownership fact_find_vehicle_ownership_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_vehicle_ownership
    ADD CONSTRAINT fact_find_vehicle_ownership_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entity(id) ON DELETE RESTRICT;


--
-- Name: fact_find_vehicle_ownership fact_find_vehicle_ownership_vehicle_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_find_vehicle_ownership
    ADD CONSTRAINT fact_find_vehicle_ownership_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.fact_find_vehicle(id) ON DELETE CASCADE;


--
-- Name: financial_planner financial_planner_business_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.financial_planner
    ADD CONSTRAINT financial_planner_business_unit_id_fkey FOREIGN KEY (business_unit_id) REFERENCES public.business_unit(id) ON DELETE RESTRICT;


--
-- Name: financial_product financial_product_product_category_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.financial_product
    ADD CONSTRAINT financial_product_product_category_fkey FOREIGN KEY (product_category) REFERENCES public.financial_product_category(code);


--
-- Name: goal goal_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.goal
    ADD CONSTRAINT goal_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.crm_case(id) ON DELETE CASCADE;


--
-- Name: investment_option linked_product___fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.investment_option
    ADD CONSTRAINT linked_product___fk FOREIGN KEY (linked_product) REFERENCES public.financial_product(rex_id);


--
-- Name: CONSTRAINT linked_product___fk ON investment_option; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON CONSTRAINT linked_product___fk ON public.investment_option IS 'Links investment options to their financial products';


--
-- PostgreSQL database dump complete
--

\unrestrict ZMAAuTc60b5WXmES8hflR4KkNU90w5kw74AJheKP3VBourH4padeZ3EV0gCZMJv

