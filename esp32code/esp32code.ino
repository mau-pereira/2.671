#include <WiFi.h>
#include <WebSocketsServer.h>
#include <ESP32Servo.h>

const char* ssid     = "AccessPoint_ESP32";
const char* password = "12345678";

const int ESC_PIN    = 26;
const int RUDDER_PIN = 25;

Servo esc;
Servo rudder;

int propeller_us = 1500;
int rudder_us    = 1500;

WebSocketsServer ws = WebSocketsServer(81);

void applyOutputs() {
  esc.writeMicroseconds(propeller_us);
  rudder.writeMicroseconds(rudder_us);
}

void parseCommand(uint8_t* payload) {
  char* msg = (char*)payload;

  char* tok = strtok(msg, ",");
  while (tok != NULL) {
    char code = tok[0];
    int  val  = atoi(tok + 1);

    if (val >= 1000 && val <= 2000) {
      if (code == 'P') propeller_us = val;
      if (code == 'R') rudder_us    = val;
    }

    tok = strtok(NULL, ",");
  }

  applyOutputs();
}

void onWebSocketEvent(uint8_t clientNum, WStype_t type,
                       uint8_t* payload, size_t length) {
  switch (type) {
    case WStype_CONNECTED:
      Serial.printf("[%u] Client connected\n", clientNum);
      break;

    case WStype_DISCONNECTED:
      Serial.printf("[%u] Client disconnected — going idle\n", clientNum);
      propeller_us = 1500;
      rudder_us    = 1500;
      applyOutputs();
      break;

    case WStype_TEXT:
      Serial.printf("[%u] Received: %s\n", clientNum, payload);
      parseCommand(payload);
      Serial.printf("  -> propeller=%d  rudder=%d\n", propeller_us, rudder_us);
      break;

    default:
      break;
  }
}

void setup() {
  Serial.begin(115200);
  delay(500);

  // --- Access Point ---
  WiFi.mode(WIFI_AP);
  WiFi.softAP(ssid, password);
  Serial.print("AP IP: ");
  Serial.println(WiFi.softAPIP());

  // --- Servos ---
  ESP32PWM::allocateTimer(0);
  ESP32PWM::allocateTimer(1);

  esc.setPeriodHertz(50);
  esc.attach(ESC_PIN, 1000, 2000);
  esc.writeMicroseconds(1500);

  rudder.setPeriodHertz(50);
  rudder.attach(RUDDER_PIN, 1000, 2000);
  rudder.writeMicroseconds(1500);

  // --- WebSocket Server ---
  ws.begin();
  ws.onEvent(onWebSocketEvent);
  Serial.println("WebSocket server started on port 81");
}

void loop() {
  ws.loop();
}
