import os
import re
import unicodedata
import psycopg2
import xml.etree.ElementTree as ET
import datetime
import boto3
from botocore.config import Config

# ===================== CONFIG =====================
DB_CONFIG = {
    "dbname": "buscalead",
    "user": "postgres",
    "password": os.environ.get("DB_PASSWORD", "@Danielfonza123"),
    "host": os.environ.get("DB_HOST", "147.93.32.112"),
    "port": "5432"
}

S3_ENDPOINT = os.environ.get("S3_ENDPOINT", "https://s3.buscalead.com")
S3_ACCESS_KEY = os.environ.get("S3_ACCESS_KEY", "eTGUOOIoq1dIijnW44HD")
S3_SECRET_KEY = os.environ.get("S3_SECRET_KEY", "N4SLZ76bDlAU9xrNVOF5qCZyxUerVVBcSBdzw6wn")
S3_BUCKET = "sitemaps"
S3_REGION = "us-east-1"

BASE_URL = "https://buscalead.com"
OUTPUT_DIR = "sitemaps"
TODAY = datetime.date.today().isoformat()

START_DATE = datetime.date(1996, 8, 1)
END_DATE = datetime.date.today()

SITUACAO_ATIVA = "02"

# ===================== 27 UFs DO BRASIL =====================
UFS = [
    "ac", "al", "ap", "am", "ba", "ce", "df", "es", "go",
    "ma", "mt", "ms", "mg", "pa", "pb", "pr", "pe", "pi",
    "rj", "rn", "rs", "ro", "rr", "sc", "sp", "se", "to"
]

# ===================== 21 SECOES CNAE (A-U) =====================
SECOES_CNAE = {
    "A": "Agricultura, Pecuaria, Producao Florestal, Pesca e Aquicultura",
    "B": "Industrias Extrativas",
    "C": "Industrias de Transformacao",
    "D": "Eletricidade e Gas",
    "E": "Agua, Esgoto, Atividades de Gestao de Residuos e Descontaminacao",
    "F": "Construcao",
    "G": "Comercio; Reparacao de Veiculos Automotores e Motocicletas",
    "H": "Transporte, Armazenagem e Correio",
    "I": "Alojamento e Alimentacao",
    "J": "Informacao e Comunicacao",
    "K": "Atividades Financeiras, de Seguros e Servicos Relacionados",
    "L": "Atividades Imobiliarias",
    "M": "Atividades Profissionais, Cientificas e Tecnicas",
    "N": "Atividades Administrativas e Servicos Complementares",
    "O": "Administracao Publica, Defesa e Seguridade Social",
    "P": "Educacao",
    "Q": "Saude Humana e Servicos Sociais",
    "R": "Artes, Cultura, Esporte e Recreacao",
    "S": "Outras Atividades de Servicos",
    "T": "Servicos Domesticos",
    "U": "Organismos Internacionais e Outras Instituicoes Extraterritoriais",
}


def slugify(text):
    text = unicodedata.normalize('NFD', text)
    text = ''.join(c for c in text if unicodedata.category(c) != 'Mn')
    text = re.sub(r'[;,]', '', text)
    text = re.sub(r'\s+', '-', text)
    text = text.lower()
    return text


SETORES_SLUGS = {letra: slugify(nome) for letra, nome in SECOES_CNAE.items()}

# ===================== FUNCOES XML =====================


def novo_urlset():
    return ET.Element("urlset", xmlns="http://www.sitemaps.org/schemas/sitemap/0.9")


def add_url(root, loc, priority="0.5", changefreq="monthly"):
    url_el = ET.SubElement(root, "url")
    loc_el = ET.SubElement(url_el, "loc")
    loc_el.text = loc
    lastmod_el = ET.SubElement(url_el, "lastmod")
    lastmod_el.text = TODAY
    cf_el = ET.SubElement(url_el, "changefreq")
    cf_el.text = changefreq
    p_el = ET.SubElement(url_el, "priority")
    p_el.text = priority


def salvar_sitemap(root, filepath):
    ET.ElementTree(root).write(filepath, encoding="utf-8", xml_declaration=True)


def gerar_sitemap_index(sitemaps, filepath):
    si = ET.Element("sitemapindex", xmlns="http://www.sitemaps.org/schemas/sitemap/0.9")
    for url in sitemaps:
        sm = ET.SubElement(si, "sitemap")
        loc = ET.SubElement(sm, "loc")
        loc.text = url
        lastmod = ET.SubElement(sm, "lastmod")
        lastmod.text = TODAY
    ET.ElementTree(si).write(filepath, encoding="utf-8", xml_declaration=True)


# ===================== CONEXAO BANCO =====================
print("Conectando ao banco...")
conn = psycopg2.connect(**DB_CONFIG)
conn.autocommit = True
cur = conn.cursor()

# ===================== OUTPUT DIR =====================
os.makedirs(OUTPUT_DIR, exist_ok=True)

all_sitemaps = []

# ===================== 1. SITEMAP PAGINAS ESTATICAS =====================
print("Gerando sitemap de paginas estaticas...")

root = novo_urlset()

static_pages = [
    (f"{BASE_URL}/", "1.0", "weekly"),
    (f"{BASE_URL}/consulta-empresa", "0.9", "weekly"),
    (f"{BASE_URL}/gerador-de-leads-gratis", "0.9", "weekly"),
    (f"{BASE_URL}/setores", "0.8", "weekly"),
    (f"{BASE_URL}/termos-de-uso", "0.3", "yearly"),
    (f"{BASE_URL}/politica-de-privacidade", "0.3", "yearly"),
    (f"{BASE_URL}/exclusao-dados", "0.2", "yearly"),
]

for loc, pri, freq in static_pages:
    add_url(root, loc, pri, freq)

path = os.path.join(OUTPUT_DIR, "sitemap-static.xml")
salvar_sitemap(root, path)
all_sitemaps.append(f"{BASE_URL}/{S3_BUCKET}/sitemap-static.xml")
print(f"  sitemap-static.xml ({len(static_pages)} URLs)")

# ===================== 2. SITEMAP SETORES =====================
print("Gerando sitemap de setores...")

root = novo_urlset()

# /setores/:slug — 21 secoes CNAE
for letra, slug in SETORES_SLUGS.items():
    add_url(root, f"{BASE_URL}/setores/{slug}", "0.7", "weekly")

path = os.path.join(OUTPUT_DIR, "sitemap-setores.xml")
salvar_sitemap(root, path)
all_sitemaps.append(f"{BASE_URL}/{S3_BUCKET}/sitemap-setores.xml")
print(f"  sitemap-setores.xml ({len(SETORES_SLUGS)} URLs)")

# ===================== 3. SITEMAP EMPRESAS POR ESTADO =====================
print("Gerando sitemap de empresas por estado...")

root = novo_urlset()

# /empresas/:uf — 27 UFs
for uf in UFS:
    add_url(root, f"{BASE_URL}/empresas/{uf}", "0.7", "weekly")

path = os.path.join(OUTPUT_DIR, "sitemap-estados.xml")
salvar_sitemap(root, path)
all_sitemaps.append(f"{BASE_URL}/{S3_BUCKET}/sitemap-estados.xml")
print(f"  sitemap-estados.xml ({len(UFS)} URLs)")

# ===================== 4. SITEMAP CNAE =====================
print("Gerando sitemaps de CNAEs...")

# Buscar todos os codigos CNAE que tem empresas ativas
cur.execute("""
    SELECT DISTINCT e.cnae_fiscal_principal
    FROM estabelecimentos e
    WHERE e.situacao_cadastral = %s
      AND e.cnae_fiscal_principal IS NOT NULL
    ORDER BY e.cnae_fiscal_principal;
""", (SITUACAO_ATIVA,))

cnae_codes = [row[0] for row in cur.fetchall()]
print(f"  Encontrados {len(cnae_codes)} CNAEs com empresas ativas")

# /consulta-cnae/:code — um sitemap por bloco de 20k
CHUNK_SIZE = 20000
for i in range(0, len(cnae_codes), CHUNK_SIZE):
    chunk = cnae_codes[i:i + CHUNK_SIZE]
    part = (i // CHUNK_SIZE) + 1

    root = novo_urlset()
    for code in chunk:
        add_url(root, f"{BASE_URL}/consulta-cnae/{code}", "0.6", "monthly")

    filename = f"sitemap-cnae-{part}.xml"
    salvar_sitemap(root, os.path.join(OUTPUT_DIR, filename))
    all_sitemaps.append(f"{BASE_URL}/{S3_BUCKET}/{filename}")
    print(f"  {filename} ({len(chunk)} URLs)")

# ===================== 5. SITEMAP CNAE x UF =====================
print("Gerando sitemaps de CNAE por estado...")

# Buscar combinacoes CNAE x UF que realmente existem
cur.execute("""
    SELECT DISTINCT e.cnae_fiscal_principal, LOWER(e.uf) as uf
    FROM estabelecimentos e
    WHERE e.situacao_cadastral = %s
      AND e.cnae_fiscal_principal IS NOT NULL
      AND e.uf IS NOT NULL
    ORDER BY e.cnae_fiscal_principal, uf;
""", (SITUACAO_ATIVA,))

cnae_uf_pairs = cur.fetchall()
print(f"  Encontradas {len(cnae_uf_pairs)} combinacoes CNAE x UF")

# /consulta-cnae/:code/:uf — dividido em blocos de 20k
for i in range(0, len(cnae_uf_pairs), CHUNK_SIZE):
    chunk = cnae_uf_pairs[i:i + CHUNK_SIZE]
    part = (i // CHUNK_SIZE) + 1

    root = novo_urlset()
    for code, uf in chunk:
        add_url(root, f"{BASE_URL}/consulta-cnae/{code}/{uf}", "0.5", "monthly")

    filename = f"sitemap-cnae-uf-{part}.xml"
    salvar_sitemap(root, os.path.join(OUTPUT_DIR, filename))
    all_sitemaps.append(f"{BASE_URL}/{S3_BUCKET}/{filename}")
    print(f"  {filename} ({len(chunk)} URLs)")

# ===================== 6. SITEMAPS EMPRESAS (por dia) =====================
print("Gerando sitemaps de empresas ativas (por dia)...")

data_atual = START_DATE

while data_atual <= END_DATE:
    data_fim = data_atual + datetime.timedelta(days=1)
    ano = data_atual.year

    ano_dir = os.path.join(OUTPUT_DIR, str(ano))
    os.makedirs(ano_dir, exist_ok=True)

    cur.execute("""
        SELECT slug
        FROM estabelecimentos
        WHERE data_inicio_atividade >= %s
          AND data_inicio_atividade < %s
          AND situacao_cadastral = %s
        ORDER BY slug;
    """, (data_atual, data_fim, SITUACAO_ATIVA))

    rows = cur.fetchall()

    if rows:
        total_urls = len(rows)

        for i in range(0, total_urls, CHUNK_SIZE):
            chunk_rows = rows[i:i + CHUNK_SIZE]
            part_num = (i // CHUNK_SIZE) + 1

            sitemap_filename = f"{data_atual}-{part_num}.xml"
            sitemap_path = os.path.join(ano_dir, sitemap_filename)

            root = novo_urlset()

            for (slug,) in chunk_rows:
                add_url(root, f"{BASE_URL}/consulta-empresa/{slug}", "0.6", "monthly")

            salvar_sitemap(root, sitemap_path)

            s3_url = f"{BASE_URL}/{S3_BUCKET}/{ano}/{sitemap_filename}"
            all_sitemaps.append(s3_url)

            print(f"  {sitemap_filename} ({len(chunk_rows)} URLs)")

    data_atual += datetime.timedelta(days=1)

# ===================== GERA sitemap_index =====================
print("Gerando sitemap_index.xml...")

sitemap_index_path = os.path.join(OUTPUT_DIR, "sitemap_index.xml")
gerar_sitemap_index(all_sitemaps, sitemap_index_path)

print(f"sitemap_index.xml criado com {len(all_sitemaps)} sitemaps.")

# ===================== UPLOAD PARA S3 =====================
print("Enviando tudo para o S3...")


def enviar_para_s3():
    s3 = boto3.client(
        "s3",
        endpoint_url=S3_ENDPOINT,
        aws_access_key_id=S3_ACCESS_KEY,
        aws_secret_access_key=S3_SECRET_KEY,
        region_name=S3_REGION,
        config=Config(signature_version="s3v4")
    )

    for root_dir, dirs, files in os.walk(OUTPUT_DIR):
        for filename in files:
            if filename == "sitemap_index.xml":
                continue

            local_path = os.path.join(root_dir, filename)
            rel_path = os.path.relpath(local_path, OUTPUT_DIR)
            s3_key = rel_path

            s3.upload_file(local_path, S3_BUCKET, s3_key, ExtraArgs={
                "ContentType": "application/xml"
            })

            print(f"  Enviado: {s3_key}")

    s3.upload_file(sitemap_index_path, S3_BUCKET, "sitemap_index.xml", ExtraArgs={
        "ContentType": "application/xml"
    })

    print("Finalizado!")


try:
    enviar_para_s3()
except Exception as e:
    print("Erro ao enviar para S3:", e)
