import os
import shutil

def create_flutter_backup():
    # 1. Folder ka naam poochna
    backup_name = input("Backup folder ka naam likhen (e.g., 30april-update): ").strip()
    
    if not backup_name:
        print("Naam dena zaroori hai!")
        return

    # Jahan script pari hai wahan naya folder banana
    current_dir = os.getcwd()
    target_dir = os.path.join(current_dir, backup_name)

    # Zaroori files aur folders ki list
    required_items = [
        'lib',
        'pubspec.yaml',
        'pubspec.lock',
        'assets',
        'android',
        'ios',
        'windows',
        'linux',
        'macos',
        'analysis_options.yaml'
    ]

    try:
        # Naya folder banana
        if not os.path.exists(target_dir):
            os.makedirs(target_dir)
            print(f"Naya folder ban gaya: {target_dir}")
        else:
            print("Is naam ka folder pehle se majood hai!")
            return

        # Files copy karna
        for item in required_items:
            source_path = os.path.join(current_dir, item)
            destination_path = os.path.join(target_dir, item)

            if os.path.exists(source_path):
                if os.path.isdir(source_path):
                    shutil.copytree(source_path, destination_path)
                    print(f"Folder copy hua: {item}")
                else:
                    shutil.copy2(source_path, destination_path)
                    print(f"File copy hui: {item}")
            else:
                print(f"Not found (Skipped): {item}")

        print(f"\nSuccess! Aapka backup '{backup_name}' tayyar hai.")
        print(f"Ab aapka folder 2.5GB ke bajaye sirf chand MBs ka hoga.")

    except Exception as e:
        print(f"Koi masla hua: {e}")

if __name__ == "__main__":
    create_flutter_backup()