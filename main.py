import os
import psycopg2
import xml.etree.ElementTree as ET
import datetime
import boto3
from botocore.config import Config

# ===================== CONFIG =====================
DB_CONFIG = {
    "dbname": "buscalead",
    "user": "postgres",
    "password": "@Danielfonza123",
    "host": "147.93.32.112",
    "port": "5432"
}

# Configuração MinIO/S3
S3_ENDPOINT = "https://s3.buscalead.com"  # ex: https://minio.seuservidor.com
S3_ACCESS_KEY = "eTGUOOIoq1dIijnW44HD"
S3_SECRET_KEY = "N4SLZ76bDlAU9xrNVOF5qCZyxUerVVBcSBdzw6wn"
S3_BUCKET = "sitemaps"
S3_REGION = "us-east-1"  # pode ser fictício no MinIO
S3_FOLDER = ""   # pasta dentro do bucket (opcional

BASE_URL = "https://buscalead.com/consulta-empresa"
OUTPUT_DIR = "sitemaps"

START_DATE = datetime.date(1996, 8, 1)
END_DATE = datetime.date.today()

# ===================== FUNÇÕES =====================


def novo_urlset():
    return ET.Element("urlset", xmlns="http://www.sitemaps.org/schemas/sitemap/0.9")


def salvar_sitemap(root, filepath):
    ET.ElementTree(root).write(
        filepath, encoding="utf-8", xml_declaration=True)


def gerar_sitemap_index(sitemaps, filepath):
    sitemap_index = ET.Element("sitemapindex", {
        "xmlns": "http://www.sitemaps.org/schemas/sitemap/0.9"
    })

    today = datetime.date.today().isoformat()

    for url in sitemaps:
        sm = ET.SubElement(sitemap_index, "sitemap")
        loc = ET.SubElement(sm, "loc")
        loc.text = url
        lastmod = ET.SubElement(sm, "lastmod")
        lastmod.text = today

    ET.ElementTree(sitemap_index).write(
        filepath, encoding="utf-8", xml_declaration=True)


# ===================== CONEXÃO BANCO =====================
print("🔄 Conectando ao banco...")
conn = psycopg2.connect(**DB_CONFIG)
conn.autocommit = True
cur = conn.cursor()

# ===================== OUTPUT DIR =====================
os.makedirs(OUTPUT_DIR, exist_ok=True)

# Índices (lista plana de URLs)
all_sitemaps = []

# ===================== LOOP POR DIA =====================
print("🚀 Gerando sitemaps diários...")

data_atual = START_DATE

while data_atual <= END_DATE:
    data_fim = data_atual + datetime.timedelta(days=1)
    ano = data_atual.year

    # garantir pasta por ano
    ano_dir = os.path.join(OUTPUT_DIR, str(ano))
    os.makedirs(ano_dir, exist_ok=True)

    sitemap_filename = f"{data_atual}.xml"
    sitemap_path = os.path.join(ano_dir, sitemap_filename)

    # Query por dia
    cur.execute("""
        SELECT slug 
        FROM estabelecimentos
        WHERE data_inicio_atividade >= %s
          AND data_inicio_atividade < %s
        ORDER BY slug;
    """, (data_atual, data_fim))

    rows = cur.fetchall()

    if rows:
        # Dividir em chunks de 20.000
        CHUNK_SIZE = 20000
        total_urls = len(rows)
        
        for i in range(0, total_urls, CHUNK_SIZE):
            chunk_rows = rows[i:i + CHUNK_SIZE]
            part_num = (i // CHUNK_SIZE) + 1
            
            # Nome do arquivo com parte: YYYY-MM-DD-1.xml, YYYY-MM-DD-2.xml, etc.
            sitemap_filename = f"{data_atual}-{part_num}.xml"
            sitemap_path = os.path.join(ano_dir, sitemap_filename)

            root = novo_urlset()

            for (slug,) in chunk_rows:
                url = ET.SubElement(root, "url")
                loc = ET.SubElement(url, "loc")
                loc.text = f"{BASE_URL}/{slug}"

                lastmod = ET.SubElement(url, "lastmod")
                lastmod.text = datetime.date.today().isoformat()

                changefreq = ET.SubElement(url, "changefreq")
                changefreq.text = "monthly"

                priority = ET.SubElement(url, "priority")
                priority.text = "0.5"

            salvar_sitemap(root, sitemap_path)

            # armazenar URL S3 futura
            s3_url = f"https://buscalead.com/{S3_BUCKET}/{ano}/{sitemap_filename}"
            all_sitemaps.append(s3_url)

            print(f"📄 Gerado {sitemap_filename} ({len(chunk_rows)} URLs)")

    data_atual += datetime.timedelta(days=1)


# ===================== GERA sitemap_index ÚNICO =====================
print("🧩 Gerando sitemap_index.xml único...")

sitemap_index_path = os.path.join(OUTPUT_DIR, "sitemap_index.xml")
gerar_sitemap_index(all_sitemaps, sitemap_index_path)

print(f"✅ sitemap_index.xml criado com {len(all_sitemaps)} sitemaps.")


# ===================== UPLOAD PARA S3 =====================
print("☁️ Enviando tudo para o S3...")


def enviar_para_s3():
    s3 = boto3.client(
        "s3",
        endpoint_url=S3_ENDPOINT,
        aws_access_key_id=S3_ACCESS_KEY,
        aws_secret_access_key=S3_SECRET_KEY,
        region_name=S3_REGION,
        config=Config(signature_version="s3v4")
    )

    # Enviar arquivos diários (mantendo a estrutura de pastas local para iterar)
    # Poderíamos iterar sobre all_sitemaps, mas iterar diretórios garante que enviamos o que foi gerado
    for root_dir, dirs, files in os.walk(OUTPUT_DIR):
        for filename in files:
            if filename == "sitemap_index.xml":
                continue  # Enviaremos separadamente no final

            local_path = os.path.join(root_dir, filename)
            
            # Calcular s3_key baseado na estrutura relativa
            # Ex: sitemaps/2024/2024-01-01.xml -> 2024/2024-01-01.xml
            rel_path = os.path.relpath(local_path, OUTPUT_DIR)
            s3_key = rel_path

            s3.upload_file(local_path, S3_BUCKET, s3_key, ExtraArgs={
                "ContentType": "application/xml"
            })

            print(f"☑️ Enviado: {s3_key}")

    # Enviar sitemap_index único
    s3.upload_file(sitemap_index_path, S3_BUCKET, "sitemap_index.xml", ExtraArgs={
        "ContentType": "application/xml"
    })

    print("🎯 Finalizado!")


try:
    enviar_para_s3()
except Exception as e:
    print("❌ Erro ao enviar para S3:", e)
