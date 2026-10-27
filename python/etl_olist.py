import pandas as pd
from pathlib import Path
from sqlalchemy import create_engine, text
from sqlalchemy.types import VARCHAR

RAW=Path("../data/raw")

tabele={}
for fisier in sorted(RAW.glob("*.csv")):
    nume=fisier.stem.replace("olist_","").replace("_dataset","")
    if nume == "geolocation":
        continue
    tabele[nume]=pd.read_csv(fisier)

for nume,df in tabele.items():
    print("="*60)
    print(f"{nume}:  {df.shape[0]:,} randuri, {df.shape[1]} coloane")
    print("-"*60)
    raport=pd.DataFrame({
        "tip":        df.dtypes.astype(str),
        "lipsa":      df.isnull().sum(),
        "lipsa_%":    (df.isnull().mean()*100).round(1),
        "exemplu":    df.iloc[0],
    })
    print(raport.to_string())


# =====================================================================
# 2. TRANSFORM
# =====================================================================

# --- 2.1 Datele calendaristice: text -> datetime ---
coloane_data = {
    "orders": ["order_purchase_timestamp", "order_approved_at",
               "order_delivered_carrier_date", "order_delivered_customer_date",
               "order_estimated_delivery_date"],
    "order_items":   ["shipping_limit_date"],
    "order_reviews": ["review_creation_date", "review_answer_timestamp"],
}
for nume, coloane in coloane_data.items():
    for col in coloane:
        tabele[nume][col] = pd.to_datetime(tabele[nume][col], errors="coerce")


# --- 2.2 Verificare: datele de livrare lipsa vs. statusul comenzii ---
orders = tabele["orders"]
print("\n--- Livrare lipsa, pe status ---")
print(pd.crosstab(orders["order_status"],
                  orders["order_delivered_customer_date"].isnull(),
                  margins=True))

# --- 2.3 Verificare: duplicate pe cheile fiecarui tabel ---
chei = {
    "customers":      ["customer_id"],
    "orders":         ["order_id"],
    "order_items":    ["order_id", "order_item_id"],
    "order_payments": ["order_id", "payment_sequential"],
    "order_reviews":  ["review_id", "order_id"],
    "products":       ["product_id"],
    "sellers":        ["seller_id"],
}
print("\n--- Duplicate pe cheie ---")
for nume, cheie in chei.items():
    print(f"{nume:15}: {tabele[nume].duplicated(subset=cheie).sum()} duplicate pe {cheie}")

rev = tabele["order_reviews"]
print("Comenzi cu mai mult de un review:", rev["order_id"].duplicated().sum())

# --- 2.4 Products: corectam numele, categorie lipsa, traducere ---
products = tabele["products"].rename(columns={
    "product_name_lenght":        "product_name_length",
    "product_description_lenght": "product_description_length",
})
products["product_category_name"] = products["product_category_name"].fillna("unknown")
products = products.merge(tabele["product_category_name_translation"],
                          on="product_category_name", how="left")
products["product_category_name_english"] = (
    products["product_category_name_english"].fillna(products["product_category_name"])
)
tabele["products"] = products
del tabele["product_category_name_translation"]     # nu mai avem nevoie de el separat


tabele["order_reviews"] = tabele["order_reviews"].drop(columns=["review_comment_title", "review_comment_message"])

# --- 2.5 Raport final: tipurile dupa transformare ---
print("\n--- Dupa TRANSFORM ---")
for nume, df in tabele.items():
    coloane_dt = [c for c in df.columns if str(df[c].dtype).startswith("datetime")]
    print(f"{nume:15}: {df.shape[0]:>7,} randuri | coloane de tip data: {coloane_dt}")


# =====================================================================
# 3. LOAD: scriem tabelele curate in SQL Server
# =====================================================================

engine = create_engine(
    "mssql+pyodbc://@localhost/Olist"
    "?driver=ODBC+Driver+18+for+SQL+Server"
    "&trusted_connection=yes&TrustServerCertificate=yes",
    fast_executemany=True,
)

print("\n--- LOAD ---")
for nume, df in tabele.items():
    tipuri = {col: VARCHAR(100) for col in df.columns if df[col].dtype == "object"}
    df.to_sql(nume, engine, if_exists="replace", index=False, chunksize=1000, dtype=tipuri)
    print(f"{nume:15}: {len(df):>7,} randuri incarcate")

# --- Verificare: citim inapoi din SQL Server cate randuri are fiecare tabel ---
print("\n--- Verificare in SQL Server ---")
with engine.connect() as conn:
    for nume in tabele:
        n = conn.execute(text(f"SELECT COUNT(*) FROM {nume}")).scalar()
        print(f"{nume:15}: {n:>7,} randuri in SQL Server")