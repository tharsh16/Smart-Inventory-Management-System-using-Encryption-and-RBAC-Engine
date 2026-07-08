from cryptography.fernet import Fernet
import os

KEY_FILE = "secret.key"


def load_key():
    """
    Load the encryption key if it exists.
    Otherwise create a new one and save it.
    """
    if os.path.exists(KEY_FILE):
        with open(KEY_FILE, "rb") as file:
            key = file.read()
    else:
        key = Fernet.generate_key()
        with open(KEY_FILE, "wb") as file:
            file.write(key)

    return key


# Load the key only once
key = load_key()

# Create Fernet object
cipher = Fernet(key)


def encrypt_data(data):
    """
    Encrypt plain text.
    Returns encrypted bytes.
    """
    return cipher.encrypt(data.encode())


def decrypt_data(encrypted_data):
    """
    Decrypt encrypted bytes.
    Returns plain text.
    """
    return cipher.decrypt(encrypted_data).decode()
