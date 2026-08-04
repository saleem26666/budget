import os
import shutil

def restore_flutter_backup():
    # 1. Backup folder ka naam poochna
    backup_name = input("Kaunsa backup restore karna hai? (e.g., 30april-update): ").strip()
    
    if not backup_name:
        print("Naam dena zaroori hai!")
        return

    # Jahan script pari hai wahan se backup dhoondna
    current_dir = os.getcwd()
    backup_path = os.path.join(current_dir, backup_name)

    # Check karna ke backup folder majood hai ya nahi
    if not os.path.exists(backup_path):
        print(f"Ghalti: '{backup_name}' naam ka koi folder nahi mila!")
        return

    print(f"Restoring from: {backup_name}...")

    # Backup ke andar jitni bhi cheezein hain unhein scan karna
    items_to_restore = os.listdir(backup_path)

    try:
        for item in items_to_restore:
            source = os.path.join(backup_path, item)
            destination = os.path.join(current_dir, item)

            # Agar folder hai to pehle purana delete karke naya copy karna (Replace)
            if os.path.isdir(source):
                if os.path.exists(destination):
                    shutil.rmtree(destination)
                shutil.copytree(source, destination)
                print(f"Folder restored/replaced: {item}")
            
            # Agar file hai to direct replace karna
            else:
                shutil.copy2(source, destination)
                print(f"File restored/replaced: {item}")

        print(f"\nSuccess! '{backup_name}' se data restore ho gaya hai.")
        print("Ab aap 'flutter pub get' chala kar project run kar sakte hain.")

    except Exception as e:
        print(f"Restore mein masla hua: {e}")

if __name__ == "__main__":
    restore_flutter_backup()