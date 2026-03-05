--
-- PostgreSQL database dump
--

\restrict ZJjicJkhzEVljbq0eKY0QIj6HM9jZThunPLlWos8Z1f8cqh2oTPKxRcI7mGdgGe

-- Dumped from database version 17.7 (Debian 17.7-3.pgdg13+1)
-- Dumped by pg_dump version 17.7 (Ubuntu 17.7-3.pgdg24.04+1)

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
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: unaccent; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA public;


--
-- Name: EXTENSION unaccent; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION unaccent IS 'text search dictionary that removes accents';


--
-- Name: atualizar_cnpj_completo(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.atualizar_cnpj_completo() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.cnpj_completo := LEFT(
        COALESCE(NEW.cnpj_basico,'') || COALESCE(NEW.cnpj_ordem,'') || COALESCE(NEW.cnpj_dv,''),
        20
    );
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.atualizar_cnpj_completo() OWNER TO postgres;

--
-- Name: estabelecimentos_generate_slug(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.estabelecimentos_generate_slug() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    razao TEXT;
    cnpj_comp TEXT;
BEGIN
    -- Busca a razao_social da empresa relacionada
    SELECT razao_social INTO razao
    FROM empresas
    WHERE cnpj_basico = NEW.cnpj_basico;

    -- Se cnpj_completo estiver nulo, usa cnpj_basico + cnpj_ordem + cnpj_dv
    cnpj_comp := COALESCE(
        NEW.cnpj_completo,
        NEW.cnpj_basico || NEW.cnpj_ordem || NEW.cnpj_dv
    );

    -- Gera slug
    NEW.slug := LEFT(
        public.slugify(
            COALESCE(razao,'empresa') || '-' || cnpj_comp
        ),
        255
    );

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.estabelecimentos_generate_slug() OWNER TO postgres;

--
-- Name: f_atualizar_tipos_telefone(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.f_atualizar_tipos_telefone() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Atualiza telefone_1_tipo
  NEW.telefone_1_tipo := CASE 
    WHEN NEW.telefone_1 IS NULL THEN NULL
    WHEN char_length(NEW.telefone_1) = 8 AND substring(NEW.telefone_1 from 1 for 1) BETWEEN '2' AND '5' THEN 'F'
    ELSE 'C'
  END;

  -- Atualiza telefone_2_tipo
  NEW.telefone_2_tipo := CASE 
    WHEN NEW.telefone_2 IS NULL THEN NULL
    WHEN char_length(NEW.telefone_2) = 8 AND substring(NEW.telefone_2 from 1 for 1) BETWEEN '2' AND '5' THEN 'F'
    ELSE 'C'
  END;

  RETURN NEW;
END;
$$;


ALTER FUNCTION public.f_atualizar_tipos_telefone() OWNER TO postgres;

--
-- Name: immutable_unaccent(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.immutable_unaccent(text) RETURNS text
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $_$
  SELECT public.unaccent($1);
$_$;


ALTER FUNCTION public.immutable_unaccent(text) OWNER TO postgres;

--
-- Name: slugify(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.slugify(text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
DECLARE
    input_text ALIAS FOR $1;
    output_text text;
BEGIN
    output_text := lower(input_text);
    output_text := unaccent(output_text);
    output_text := regexp_replace(output_text, '\s+', '-', 'g');
    output_text := regexp_replace(output_text, '[^a-z0-9\-]', '', 'g');
    output_text := regexp_replace(output_text, '-+', '-', 'g');
    output_text := regexp_replace(output_text, '(^-+|-+$)', '', 'g');
    RETURN output_text;
END;
$_$;


ALTER FUNCTION public.slugify(text) OWNER TO postgres;

--
-- Name: trg_update_email_info(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_update_email_info() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    dom TEXT;
BEGIN
    -- Se o campo correio_eletronico for NULL → deixa tudo NULL
    IF NEW.correio_eletronico IS NULL THEN
        NEW.email_dominio := NULL;
        NEW.email_tipo := NULL;
        RETURN NEW;
    END IF;

    -- Extrair domínio
    dom := lower(split_part(NEW.correio_eletronico, '@', 2));
    NEW.email_dominio := dom;

    -- Classificar tipo de email
    IF dom ILIKE '%contab%' THEN
        NEW.email_tipo := 'contabilidade';

    ELSIF dom IN (
        'gmail.com','outlook.com','hotmail.com','live.com',
        'yahoo.com','icloud.com','aol.com','gmx.com','zoho.com',
        'proton.me','tutanota.com','mail.com',
        'bol.com.br','uol.com.br','terra.com.br','ig.com.br'
    ) THEN
        NEW.email_tipo := 'particular';

    ELSE
        NEW.email_tipo := 'corporativo';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.trg_update_email_info() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: cnaes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.cnaes (
    codigo character varying(7) NOT NULL,
    descricao text,
    data_criacao timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    data_atualizacao timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.cnaes OWNER TO postgres;

--
-- Name: dados_simples; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.dados_simples (
    cnpj_basico character varying(8) NOT NULL,
    opcao_pelo_simples character varying(1),
    data_opcao_pelo_simples date,
    data_exclusao_do_simples date,
    opcao_pelo_mei character varying(1),
    data_opcao_pelo_mei date,
    data_exclusao_do_mei date,
    data_criacao timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    data_atualizacao timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.dados_simples OWNER TO postgres;

--
-- Name: empresas; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.empresas (
    cnpj_basico character varying(8) NOT NULL,
    razao_social text,
    natureza_juridica character varying(4),
    qualificacao_responsavel character varying(2),
    capital_social double precision,
    porte character varying(2),
    ente_federativo_responsavel text,
    data_criacao timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    data_atualizacao timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.empresas OWNER TO postgres;

--
-- Name: estabelecimentos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.estabelecimentos (
    cnpj_basico character varying(8) NOT NULL,
    cnpj_ordem character varying(4) NOT NULL,
    cnpj_dv character varying(2) NOT NULL,
    identificador_matriz_filial character varying(1),
    nome_fantasia text,
    situacao_cadastral character varying(2),
    data_situacao_cadastral date,
    motivo_situacao_cadastral character varying(2),
    nome_cidade_exterior text,
    pais character varying(3),
    data_inicio_atividade date,
    cnae_fiscal_principal character varying(7),
    cnae_fiscal_secundaria text,
    tipo_logradouro text,
    logradouro text,
    numero text,
    complemento text,
    bairro text,
    cep character varying(8),
    uf character varying(2),
    municipio character varying(7),
    ddd_1 character varying(4),
    telefone_1 character varying(8),
    ddd_2 character varying(4),
    telefone_2 character varying(8),
    ddd_fax character varying(4),
    fax character varying(8),
    correio_eletronico text,
    situacao_especial text,
    data_situacao_especial date,
    data_criacao timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    data_atualizacao timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    cnpj_completo character varying(20),
    slug character varying(255),
    telefone_2_tipo character varying(1),
    telefone_1_tipo character varying(1),
    processed boolean DEFAULT false,
    email_dominio text,
    email_tipo character varying(20)
);


ALTER TABLE public.estabelecimentos OWNER TO postgres;

--
-- Name: estados_aux; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.estados_aux (
    codigo_uf integer NOT NULL,
    uf character varying(2) NOT NULL,
    nome character varying(100) NOT NULL,
    latitude real NOT NULL,
    longitude real NOT NULL,
    regiao character varying(12) NOT NULL
);


ALTER TABLE public.estados_aux OWNER TO postgres;

--
-- Name: motivos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.motivos (
    codigo character varying(2) NOT NULL,
    descricao text,
    data_criacao timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    data_atualizacao timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.motivos OWNER TO postgres;

--
-- Name: municipios; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.municipios (
    codigo character varying(7) NOT NULL,
    descricao text,
    data_criacao timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    data_atualizacao timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.municipios OWNER TO postgres;

--
-- Name: municipios_aux; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.municipios_aux (
    codigo_ibge integer NOT NULL,
    nome character varying(100) NOT NULL,
    latitude real NOT NULL,
    longitude real NOT NULL,
    capital boolean NOT NULL,
    codigo_uf integer NOT NULL,
    siafi_id character varying(4) NOT NULL,
    ddd integer NOT NULL,
    fuso_horario character varying(32) NOT NULL
);


ALTER TABLE public.municipios_aux OWNER TO postgres;

--
-- Name: naturezas_juridicas; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.naturezas_juridicas (
    codigo character varying(4) NOT NULL,
    descricao text,
    data_criacao timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    data_atualizacao timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.naturezas_juridicas OWNER TO postgres;

--
-- Name: paises; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.paises (
    codigo character varying(3) NOT NULL,
    descricao text,
    data_criacao timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    data_atualizacao timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.paises OWNER TO postgres;

--
-- Name: processed_files; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.processed_files (
    directory character varying(50) NOT NULL,
    filename character varying(255) NOT NULL,
    processed_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.processed_files OWNER TO postgres;

--
-- Name: qualificacoes_socios; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.qualificacoes_socios (
    codigo character varying(2) NOT NULL,
    descricao text,
    data_criacao timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    data_atualizacao timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.qualificacoes_socios OWNER TO postgres;

--
-- Name: socios; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.socios (
    cnpj_basico character varying(8) NOT NULL,
    identificador_de_socio character varying(1) NOT NULL,
    nome_socio text,
    cnpj_cpf_do_socio character varying(14),
    qualificacao_do_socio character varying(2),
    data_entrada_sociedade date,
    pais character varying(3),
    representante_legal character varying(11),
    nome_do_representante text,
    qualificacao_do_representante_legal character varying(2),
    faixa_etaria character varying(1),
    data_criacao timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    data_atualizacao timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS socios (
    cnpj_basico VARCHAR(8) NOT NULL,
    identificador_de_socio VARCHAR(1) NOT NULL,
    nome_socio TEXT,
    cnpj_cpf_do_socio VARCHAR(14),
    qualificacao_do_socio VARCHAR(2) REFERENCES qualificacoes_socios(codigo),
    data_entrada_sociedade DATE,
    pais VARCHAR(3),
    representante_legal VARCHAR(11),
    nome_do_representante TEXT,
    qualificacao_do_representante_legal VARCHAR(2),
    faixa_etaria VARCHAR(1),
    data_criacao TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    data_atualizacao TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    FOREIGN KEY (cnpj_basico) REFERENCES empresas(cnpj_basico) ON DELETE CASCADE
);


ALTER TABLE public.socios OWNER TO postgres;

--
-- Name: cnaes cnaes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cnaes
    ADD CONSTRAINT cnaes_pkey PRIMARY KEY (codigo);


--
-- Name: dados_simples dados_simples_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dados_simples
    ADD CONSTRAINT dados_simples_pkey PRIMARY KEY (cnpj_basico);


--
-- Name: empresas empresas_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.empresas
    ADD CONSTRAINT empresas_pkey PRIMARY KEY (cnpj_basico);


--
-- Name: estabelecimentos estabelecimentos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.estabelecimentos
    ADD CONSTRAINT estabelecimentos_pkey PRIMARY KEY (cnpj_basico, cnpj_ordem, cnpj_dv);


--
-- Name: estados_aux estados_aux_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.estados_aux
    ADD CONSTRAINT estados_aux_pkey PRIMARY KEY (codigo_uf);


--
-- Name: motivos motivos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.motivos
    ADD CONSTRAINT motivos_pkey PRIMARY KEY (codigo);


--
-- Name: municipios_aux municipios_aux_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.municipios_aux
    ADD CONSTRAINT municipios_aux_pkey PRIMARY KEY (codigo_ibge);


--
-- Name: municipios_aux municipios_aux_siafi_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.municipios_aux
    ADD CONSTRAINT municipios_aux_siafi_id_key UNIQUE (siafi_id);


--
-- Name: municipios municipios_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.municipios
    ADD CONSTRAINT municipios_pkey PRIMARY KEY (codigo);


--
-- Name: naturezas_juridicas naturezas_juridicas_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.naturezas_juridicas
    ADD CONSTRAINT naturezas_juridicas_pkey PRIMARY KEY (codigo);


--
-- Name: paises paises_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.paises
    ADD CONSTRAINT paises_pkey PRIMARY KEY (codigo);


--
-- Name: processed_files processed_files_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.processed_files
    ADD CONSTRAINT processed_files_pkey PRIMARY KEY (directory, filename);


--
-- Name: qualificacoes_socios qualificacoes_socios_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.qualificacoes_socios
    ADD CONSTRAINT qualificacoes_socios_pkey PRIMARY KEY (codigo);


--
-- Name: idx_capital_social; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_capital_social ON public.empresas USING btree (capital_social);


--
-- Name: idx_cnaes_descricao_trgm; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_cnaes_descricao_trgm ON public.cnaes USING gin (public.immutable_unaccent(descricao) public.gin_trgm_ops);


--
-- Name: idx_data_cnpj_slug; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_data_cnpj_slug ON public.estabelecimentos USING btree (data_inicio_atividade, cnpj_completo, slug);


--
-- Name: idx_empresas_natureza; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_empresas_natureza ON public.empresas USING btree (natureza_juridica) WHERE (natureza_juridica IS NOT NULL);


--
-- Name: idx_empresas_natureza_capital; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_empresas_natureza_capital ON public.empresas USING btree (natureza_juridica, capital_social) WHERE ((natureza_juridica IS NOT NULL) AND (capital_social IS NOT NULL));


--
-- Name: idx_empresas_natureza_capital_porte; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_empresas_natureza_capital_porte ON public.empresas USING btree (natureza_juridica, capital_social, porte);


--
-- Name: idx_empresas_porte; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_empresas_porte ON public.empresas USING btree (porte) WHERE (porte IS NOT NULL);


--
-- Name: idx_estab_cnae_estado_situacao_data_matriz; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_estab_cnae_estado_situacao_data_matriz ON public.estabelecimentos USING btree (cnae_fiscal_principal, uf, situacao_cadastral, data_inicio_atividade, identificador_matriz_filial) WHERE ((cnae_fiscal_principal IS NOT NULL) AND (situacao_cadastral IS NOT NULL) AND (uf IS NOT NULL));


--
-- Name: idx_estab_cnae_uf_municipio_data_sit; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_estab_cnae_uf_municipio_data_sit ON public.estabelecimentos USING btree (cnae_fiscal_principal, uf, municipio, situacao_cadastral, data_inicio_atividade DESC);


--
-- Name: idx_estab_matriz_filial; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_estab_matriz_filial ON public.estabelecimentos USING btree (identificador_matriz_filial);


--
-- Name: idx_estabelecimentos_ativos; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_estabelecimentos_ativos ON public.estabelecimentos USING btree (situacao_cadastral, data_inicio_atividade DESC) WHERE ((situacao_cadastral)::text = '02'::text);


--
-- Name: idx_estabelecimentos_bairro_trgm; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_estabelecimentos_bairro_trgm ON public.estabelecimentos USING gin (bairro public.gin_trgm_ops);


--
-- Name: idx_estabelecimentos_cep; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_estabelecimentos_cep ON public.estabelecimentos USING btree (cep) WHERE (cep IS NOT NULL);


--
-- Name: idx_estabelecimentos_cnae; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_estabelecimentos_cnae ON public.estabelecimentos USING btree (cnae_fiscal_principal) WHERE (cnae_fiscal_principal IS NOT NULL);


--
-- Name: idx_estabelecimentos_cnae_combo; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_estabelecimentos_cnae_combo ON public.estabelecimentos USING btree (cnae_fiscal_principal, situacao_cadastral, data_inicio_atividade, uf, municipio);


--
-- Name: idx_estabelecimentos_cnpj; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_estabelecimentos_cnpj ON public.estabelecimentos USING btree (cnpj_completo) WHERE (cnpj_completo IS NOT NULL);


--
-- Name: idx_estabelecimentos_cnpj_data; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_estabelecimentos_cnpj_data ON public.estabelecimentos USING btree (data_inicio_atividade DESC, cnpj_completo);


--
-- Name: idx_estabelecimentos_data_criacao; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_estabelecimentos_data_criacao ON public.estabelecimentos USING btree (data_criacao);


--
-- Name: idx_estabelecimentos_data_inicio_desc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_estabelecimentos_data_inicio_desc ON public.estabelecimentos USING btree (data_inicio_atividade DESC);


--
-- Name: idx_estabelecimentos_email_not_null; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_estabelecimentos_email_not_null ON public.estabelecimentos USING btree (correio_eletronico) WHERE (correio_eletronico IS NOT NULL);


--
-- Name: idx_estabelecimentos_estado; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_estabelecimentos_estado ON public.estabelecimentos USING btree (uf) WHERE (uf IS NOT NULL);


--
-- Name: idx_estabelecimentos_identificador; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_estabelecimentos_identificador ON public.estabelecimentos USING btree (identificador_matriz_filial) WHERE (identificador_matriz_filial IS NOT NULL);


--
-- Name: idx_estabelecimentos_municipio; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_estabelecimentos_municipio ON public.estabelecimentos USING btree (municipio) WHERE (municipio IS NOT NULL);


--
-- Name: idx_estabelecimentos_natureza; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_estabelecimentos_natureza ON public.empresas USING btree (natureza_juridica) WHERE (natureza_juridica IS NOT NULL);


--
-- Name: idx_estabelecimentos_porte; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_estabelecimentos_porte ON public.empresas USING btree (porte) WHERE (porte IS NOT NULL);


--
-- Name: idx_estabelecimentos_processed; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_estabelecimentos_processed ON public.estabelecimentos USING btree (processed);


--
-- Name: idx_estabelecimentos_processed_cnpj; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_estabelecimentos_processed_cnpj ON public.estabelecimentos USING btree (processed, cnpj_completo);


--
-- Name: idx_estabelecimentos_situacao; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_estabelecimentos_situacao ON public.estabelecimentos USING btree (situacao_cadastral) WHERE (situacao_cadastral IS NOT NULL);


--
-- Name: idx_estabelecimentos_slug_btree; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_estabelecimentos_slug_btree ON public.estabelecimentos USING btree (slug);


--
-- Name: idx_estabelecimentos_slug_trgm; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_estabelecimentos_slug_trgm ON public.estabelecimentos USING gin (slug public.gin_trgm_ops);


--
-- Name: idx_natureza_juridica; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_natureza_juridica ON public.empresas USING btree (natureza_juridica);


--
-- Name: idx_opcao_pelo_mei_n; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_opcao_pelo_mei_n ON public.dados_simples USING btree (opcao_pelo_mei) WHERE ((opcao_pelo_mei)::text = 'N'::text);


--
-- Name: idx_opcao_pelo_mei_s; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_opcao_pelo_mei_s ON public.dados_simples USING btree (opcao_pelo_mei) WHERE ((opcao_pelo_mei)::text = 'S'::text);


--
-- Name: idx_opcao_pelo_simples_n; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_opcao_pelo_simples_n ON public.dados_simples USING btree (opcao_pelo_simples) WHERE ((opcao_pelo_simples)::text = 'N'::text);


--
-- Name: idx_opcao_pelo_simples_s; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_opcao_pelo_simples_s ON public.dados_simples USING btree (opcao_pelo_simples) WHERE ((opcao_pelo_simples)::text = 'S'::text);


--
-- Name: idx_situacao_cadastral; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_situacao_cadastral ON public.estabelecimentos USING btree (situacao_cadastral);


--
-- Name: idx_uf; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_uf ON public.estabelecimentos USING btree (uf);


--
-- Name: estabelecimentos trg_atualizar_tipos_telefone; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_atualizar_tipos_telefone BEFORE INSERT OR UPDATE ON public.estabelecimentos FOR EACH ROW EXECUTE FUNCTION public.f_atualizar_tipos_telefone();


--
-- Name: estabelecimentos trg_email_tipo; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_email_tipo BEFORE INSERT OR UPDATE OF correio_eletronico ON public.estabelecimentos FOR EACH ROW EXECUTE FUNCTION public.trg_update_email_info();


--
-- Name: estabelecimentos trigger_cnpj_completo; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_cnpj_completo BEFORE INSERT OR UPDATE ON public.estabelecimentos FOR EACH ROW EXECUTE FUNCTION public.atualizar_cnpj_completo();


--
-- Name: estabelecimentos trigger_estabelecimentos_slug; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_estabelecimentos_slug BEFORE INSERT OR UPDATE ON public.estabelecimentos FOR EACH ROW EXECUTE FUNCTION public.estabelecimentos_generate_slug();


--
-- Name: empresas empresas_natureza_juridica_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.empresas
    ADD CONSTRAINT empresas_natureza_juridica_fkey FOREIGN KEY (natureza_juridica) REFERENCES public.naturezas_juridicas(codigo);


--
-- Name: estabelecimentos estabelecimentos_cnae_fiscal_principal_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.estabelecimentos
    ADD CONSTRAINT estabelecimentos_cnae_fiscal_principal_fkey FOREIGN KEY (cnae_fiscal_principal) REFERENCES public.cnaes(codigo);


--
-- Name: estabelecimentos estabelecimentos_cnpj_basico_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.estabelecimentos
    ADD CONSTRAINT estabelecimentos_cnpj_basico_fkey FOREIGN KEY (cnpj_basico) REFERENCES public.empresas(cnpj_basico) ON DELETE CASCADE;


--
-- Name: estabelecimentos estabelecimentos_motivo_situacao_cadastral_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.estabelecimentos
    ADD CONSTRAINT estabelecimentos_motivo_situacao_cadastral_fkey FOREIGN KEY (motivo_situacao_cadastral) REFERENCES public.motivos(codigo);


--
-- Name: estabelecimentos estabelecimentos_municipio_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.estabelecimentos
    ADD CONSTRAINT estabelecimentos_municipio_fkey FOREIGN KEY (municipio) REFERENCES public.municipios(codigo);


--
-- Name: estabelecimentos estabelecimentos_pais_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.estabelecimentos
    ADD CONSTRAINT estabelecimentos_pais_fkey FOREIGN KEY (pais) REFERENCES public.paises(codigo);


--
-- Name: municipios_aux municipios_aux_codigo_uf_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.municipios_aux
    ADD CONSTRAINT municipios_aux_codigo_uf_fkey FOREIGN KEY (codigo_uf) REFERENCES public.estados_aux(codigo_uf);


--
-- Name: socios socios_cnpj_basico_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.socios
    ADD CONSTRAINT socios_cnpj_basico_fkey FOREIGN KEY (cnpj_basico) REFERENCES public.empresas(cnpj_basico) ON DELETE CASCADE;


--
-- Name: socios socios_qualificacao_do_socio_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.socios
    ADD CONSTRAINT socios_qualificacao_do_socio_fkey FOREIGN KEY (qualificacao_do_socio) REFERENCES public.qualificacoes_socios(codigo);


--
-- PostgreSQL database dump complete
--

\unrestrict ZJjicJkhzEVljbq0eKY0QIj6HM9jZThunPLlWos8Z1f8cqh2oTPKxRcI7mGdgGe

