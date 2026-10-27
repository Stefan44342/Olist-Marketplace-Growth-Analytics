from sqlalchemy import create_engine, text

# --- ADRESA depozitului ---
SERVER   = "localhost"                       # numele serverului din SSMS
DATABASE = "Olist"                           # baza pe care ai creat-o
DRIVER   = "ODBC Driver 18 for SQL Server"   # driverul gasit in ODBC Data Sources

# --- MOTORUL (conexiunea) ---
engine = create_engine(
    f"mssql+pyodbc://@{SERVER}/{DATABASE}"
    f"?driver={DRIVER.replace(' ', '+')}"
    "&trusted_connection=yes"
    "&TrustServerCertificate=yes"
)

# --- TESTUL ---
with engine.connect() as conn:
    rezultat = conn.execute(text("SELECT DB_NAME()")).scalar()
    print("Conectat la baza:", rezultat)