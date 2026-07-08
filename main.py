from database import create_tables, store_inventory, fetch_inventory
from auth_engine import login
from crypto_engine import encrypt_data, decrypt_data

create_tables()

print("======================================")
print(" SMART INVENTORY MANAGEMENT SYSTEM ")
print("======================================")

username = input("Enter Username: ")
password = input("Enter Password: ")

role = login(username, password)

if role is None:
    print("\nInvalid Username or Password!")
    exit()

print(f"\nLogin Successful")
print(f"Role : {role}")

while True:

    print("\n========== MENU ==========")
    print("1. Add Inventory")
    print("2. View Inventory")
    print("3. Exit")

    choice = input("Enter your choice: ")

    if choice == "1":

        item_id = input("Enter Item ID: ")
        item_name = input("Enter Item Name: ")
        quantity = input("Enter Quantity: ")

        inventory_data = f"ID:{item_id}, Name:{item_name}, Quantity:{quantity}"

        encrypted = encrypt_data(inventory_data)

        store_inventory(encrypted.decode(), username)

        print("\nInventory Stored Successfully!")

    elif choice == "2":

        records = fetch_inventory()

        if len(records) == 0:
            print("\nNo Inventory Records Found.")
            continue

        print("\n=========== INVENTORY ===========")

        for record in records:

            print("\nRecord ID :", record[0])
            print("Added By  :", record[2])
            print("Timestamp :", record[3])

            if role in ["ADMIN", "MANAGER"]:

                try:
                    decrypted = decrypt_data(record[1].encode())
                    print("Inventory :", decrypted)

                except Exception:
                    print("Unable to decrypt this record.")

            else:

                print("Encrypted :", record[1])

    elif choice == "3":

        print("\nThank You!")
        break

    else:

        print("\nInvalid Choice.")
