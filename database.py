import sqlite3

DB_NAME = "inventory.db"


def connect():
    return sqlite3.connect(DB_NAME)


def create_tables():
    conn = connect()
    cursor = conn.cursor()

    # Users Table
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE,
        password TEXT,
        plain_password TEXT,
        role TEXT
    )
    """)

    # Inventory Table
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS inventory (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        encrypted_data TEXT NOT NULL,
        added_by TEXT NOT NULL,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
    )
    """)

    conn.commit()
    conn.close()


def store_inventory(encrypted_data, username):
    conn = connect()
    cursor = conn.cursor()

    cursor.execute(
        """
        INSERT INTO inventory (encrypted_data, added_by)
        VALUES (?, ?)
        """,
        (encrypted_data, username)
    )

    conn.commit()
    conn.close()


def fetch_inventory():
    conn = connect()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT id,
               encrypted_data,
               added_by,
               timestamp
        FROM inventory
        ORDER BY id
    """)

    records = cursor.fetchall()

    conn.close()

    return records


def fetch_users():
    conn = connect()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT username,
               plain_password,
               role
        FROM users
        ORDER BY username
    """)

    users = cursor.fetchall()

    conn.close()

    return users
