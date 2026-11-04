# Spectrum identity fixtures

These are minimal, synthetic Linux uevent fixtures, not new hardware captures.
`c987.uevent` represents the currently supported `048d:c987` identity.
`unknown-product.uevent` deliberately keeps the same vendor and name but changes
the product: it must not acquire the c987 LED map, calibration, or transport.

For a verified keyboard addition, include sanitized identity evidence and
independently verified LED addresses, layout, protocol, and calibration output.
A similar product name or vendor is not verification.
