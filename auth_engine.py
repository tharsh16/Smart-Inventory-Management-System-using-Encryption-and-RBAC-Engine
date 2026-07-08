import hashlib
from database import connect


def hash_password(password):
    return hashlib.sha256(password.encode()).hexdigest()


def register(username, password, role):
    conn = connect()
    cursor = conn.cursor()

    hashed_password = hash_password(password)

    cursor.execute("""
        INSERT INTO users (username, password, plain_password, role)
        VALUES (?, ?, ?, ?)
    """, (username, hashed_password, password, role))

    conn.commit()
    conn.close()


def login(username, password):
    conn = connect()
    cursor = conn.cursor()

    hashed_password = hash_password(password)

    cursor.execute("""
        SELECT role
        FROM users
        WHERE username = ? AND password = ?
    """, (username, hashed_password))

    result = cursor.fetchone()

    conn.close()

    if result:
        return result[0]
    else:
        return None
