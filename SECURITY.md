# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability in this SmartThings Edge driver, please report it responsibly:

### For Security Issues:
- **DO NOT** open a public GitHub issue
- Email: xeudoxus@gmail.com
- Use GitHub's private vulnerability reporting if available

### For General Bugs:
- Open a [GitHub Issue](https://github.com/xeudoxus/pitboss-grill-driver/issues)

## Security Considerations

This driver:
- Communicates directly with IoT/ESP32/Grill devices on your local network
- Does not store or transmit personal data to external services
- Uses time-based authentication with the grill's ESP32 controller
- Operates entirely within your local network (no cloud dependency)

## Best Practices for Users

1. **Network Security**: Ensure your home WiFi network is properly secured
2. **Change Default Grill Password**: **CRITICAL** - Change your grill's default password from the factory setting using the official Pit Boss app. The default password is often easily guessable and poses a security risk.
3. **Device Updates**: Keep your Pit Boss grill firmware updated
4. **Hub Security**: Keep your SmartThings hub firmware current
5. **Review Logs**: Monitor device logs for any unusual activity

## Responsible Disclosure

We follow responsible disclosure practices and will:
- Acknowledge receipt of vulnerability reports within 48 hours
- Provide estimated timeline for fixes
- Credit security researchers (with permission)
- Coordinate disclosure timing
