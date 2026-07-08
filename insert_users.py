
from database import create_tables
from auth_engine import register

# Create tables (safe to call even if they already exist)
create_tables()

# Default users
users = [
    ("admin", "admin123", "ADMIN"),
    ("manager1", "manager123", "MANAGER"),
    ("manager2", "manager456", "MANAGER"),
    ("staff1", "staff123", "STAFF"),
    ("staff2", "staff456", "STAFF"),
    ("staff3", "staff789", "STAFF"),
    ("user1", "user123", "USER"),
    ("user2", "user456", "USER"),
    ("user3", "user789", "USER"),
    ("auditor", "audit123", "AUDITOR")
]

for username, password, role in users:
    try:
        register(username, password, role)
        print(f"{username} added successfully.")
    except Exception:
        print(f"{username} already exists.")

print("\nAll users processed successfully.")
