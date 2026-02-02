import requests
import json
import sys

BASE_URL = "https://betunnel.worldstories.net"

def analyze_backend(username, password):
    session = requests.Session()
    
    # 1. Login
    print(f"Logging in as {username}...", flush=True)
    login_url = f"{BASE_URL}/api/auth/login/"
    try:
        resp = session.post(login_url, json={"username": username, "password": password})
        if resp.status_code != 200:
            print(f"Login failed: {resp.status_code} {resp.text}")
            return
        
        data = resp.json()
        token = data.get("access")
        if not token:
             # Try nested 'data'
             token = data.get("data", {}).get("access")
        
        if not token:
            print("No access token found in login response.")
            print(json.dumps(data, indent=2))
            return

        headers = {"Authorization": f"Bearer {token}"}
        print("Login successful.")

    except Exception as e:
        print(f"Login exception: {e}")
        return

    # 2. Get Rooms
    print("\nFetching Rooms...")
    try:
        rooms_resp = session.get(f"{BASE_URL}/api/support-rooms/", headers=headers)
        if rooms_resp.status_code != 200:
             # Try /api/rooms/ if support-rooms fails
             rooms_resp = session.get(f"{BASE_URL}/api/rooms/", headers=headers)
        
        if rooms_resp.status_code != 200:
            print(f"Failed to get rooms: {rooms_resp.status_code}")
            return
            
        rooms = rooms_resp.json()
        print(f"Found {len(rooms)} rooms.")
        
        target_room = None
        for room in rooms:
            print(f"- Room {room.get('id')}: {room.get('name')}")
            if "Player Support 2" in room.get('name', ''):
                target_room = room
        
        if not target_room and rooms:
            target_room = rooms[0]
            
        if not target_room:
            print("No rooms available.")
            return

    except Exception as e:
        print(f"Get support-rooms exception: {e}")
        return

    # 2.5 Get Active Chats (Queue List) explicitly
    print("\nFetching Active Chats (/api/rooms/)...")
    try:
        active_resp = session.get(f"{BASE_URL}/api/rooms/", headers=headers)
        if active_resp.status_code == 200:
            active_data = active_resp.json()
            # Handle potential pagination wrapper
            if isinstance(active_data, dict) and 'data' in active_data:
                active_list = active_data['data']
            elif isinstance(active_data, list):
                active_list = active_data
            else:
                active_list = []
            
            print(f"pdf Found {len(active_list)} active chats.")
            if active_list:
                print("\n--- SAMPLE ACTIVE CHAT ROOM STRUCTURE ---")
                print(json.dumps(active_list[0], indent=2))
        else:
             print(f"Failed to fetch active chats: {active_resp.status_code}")
    except Exception as e:
        print(f"Get Active Chats exception: {e}")

    # 3. Get Messages
    print(f"\nFetching Messages for Room: {target_room.get('name')} (ID: {target_room.get('id')})...")
    try:
        msg_url = f"{BASE_URL}/api/rooms/{target_room.get('id')}/messages/"
        msg_resp = session.get(msg_url, headers=headers)
        
        if msg_resp.status_code != 200:
            print(f"Failed to get messages: {msg_resp.status_code} {msg_resp.text}")
            return
            
        messages = msg_resp.json()
        print(f"Found {len(messages)} messages.")
        
        if messages:
            print("\n--- SAMPLE MESSAGE STRUCTURE ---")
            print(json.dumps(messages[-1], indent=2)) # Print last message
            
            print("\n--- SENDER FIELD ANALYSIS ---")
            sender = messages[-1].get('sender')
            print(f"Sender value: {sender}")
            print(f"Sender type: {type(sender)}")
            
    except Exception as e:
        print(f"Get Messages exception: {e}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python debug_backend.py <username> <password>")
    else:
        analyze_backend(sys.argv[1], sys.argv[2])
