const fs = require('fs');
const https = require('https');

const BASE_URL = "https://betunnel.worldstories.net";
const USERNAME = process.argv[2];
const PASSWORD = process.argv[3];
const LOG_FILE = 'debug_output.txt';

function log(message) {
    const msg = message + '\n';
    fs.appendFileSync(LOG_FILE, msg);
    console.log(message);
}

function request(method, path, body = null, headers = {}) {
    return new Promise((resolve, reject) => {
        const url = new URL(BASE_URL + path);
        const options = {
            method: method,
            headers: {
                'Content-Type': 'application/json',
                ...headers
            }
        };

        const req = https.request(url, options, (res) => {
            let data = '';
            res.on('data', (chunk) => data += chunk);
            res.on('end', () => {
                log(`Response ${path}: ${res.statusCode}`);
                if (res.statusCode >= 200 && res.statusCode < 300) {
                    try {
                        resolve(JSON.parse(data));
                    } catch (e) {
                        // Maybe empty or text
                        resolve(data);
                    }
                } else {
                    log(`Error body: ${data}`);
                    resolve(null);
                }
            });
        });

        req.on('error', (e) => {
            log(`Request Error: ${e.message}`);
            resolve(null);
        });

        if (body) {
            req.write(JSON.stringify(body));
        }
        req.end();
    });
}

async function run() {
    fs.writeFileSync(LOG_FILE, `Starting debug for ${USERNAME}...\n`);

    // 1. Login
    log('Logging in...');
    const loginData = await request('POST', '/api/auth/login/', { username: USERNAME, password: PASSWORD });

    if (!loginData) {
        log('Login failed.');
        return;
    }

    const token = loginData.access || (loginData.data && loginData.data.access);
    if (!token) {
        log('No token in response: ' + JSON.stringify(loginData));
        return;
    }
    log('Login successful.');

    const headers = { 'Authorization': `Bearer ${token}` };

    // 2. Get Rooms
    log('Fetching rooms...');
    let rooms = await request('GET', '/api/support-rooms/', null, headers);
    if (!rooms) {
        log('Retry with /api/rooms/');
        rooms = await request('GET', '/api/rooms/', null, headers);
    }

    if (!rooms || !Array.isArray(rooms)) {
        log('Could not fetch rooms or not an array: ' + JSON.stringify(rooms));
        return;
    }

    log(`Found ${rooms.length} rooms.`);

    let targetRoom = rooms.find(r => r.name && r.name.includes('Player Support 2'));
    if (!targetRoom && rooms.length > 0) targetRoom = rooms[0];

    if (!targetRoom) {
        log('No rooms available.');
        return;
    }

    log(`Target Room: ${targetRoom.name} (${targetRoom.id})`);

    // 3. Get Messages
    log('Fetching messages...');
    const messages = await request('GET', `/api/rooms/${targetRoom.id}/messages/`, null, headers);

    if (!messages || !Array.isArray(messages)) {
        log('Could not fetch messages.');
        return;
    }

    log(`Found ${messages.length} messages.`);

    if (messages.length > 0) {
        const lastMsg = messages[messages.length - 1];
        log('\n--- SAMPLE MESSAGE JSON ---');
        log(JSON.stringify(lastMsg, null, 2));

        log('\n--- SENDER TYPE ANALYSIS ---');
        const sender = lastMsg.sender;
        if (typeof sender === 'object' && sender !== null) {
            log('Sender is OBJECT.');
            log(JSON.stringify(sender));
        } else {
            log(`Sender is PRIMITIVE: ${typeof sender} = ${sender}`);
            // If it's just an ID, that confirms our hypothesis
        }
    } else {
        log('No messages in this room to analyze.');
    }
}

run();
