
void setup() {
    Serial.begin(115200);
    Serial.setTimeout(1000);

    Serial.println("=== FPGA UART Sender ===");
    Serial.println("Enter a number (0-255):");
}

void loop() {
    if (Serial.available() > 0) {
        String input = Serial.readStringUntil('\n');
        input.trim();

        if (input.length() == 0) return;

        // Validate input
        for (unsigned int i = 0; i < input.length(); i++) {
            if (!isDigit(input[i])) {
                Serial.println("Invalid input! Enter 0-255:");
                return;
            }
        }

        long value = input.toInt();

        if (value > 255) {
            Serial.println("Out of range! Enter 0-255:");
            return;
        }

        Serial.print("Sending: ");
        Serial.println(value);

        // Transmit ONE byte through physical TX (D1)
        Serial.write((uint8_t)value);
    }
}
