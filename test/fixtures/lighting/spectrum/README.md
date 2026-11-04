# Spectrum identity fixtures

These small Linux uevent files were written for tests. `c987.uevent` contains
the supported keyboard's USB IDs, `048d:c987`. `unknown-product.uevent` keeps
the same vendor and device name but changes the product ID to `c988`. Tests use
it to check that an unsupported keyboard gets no c987 LED mapping, color
adjustments, or writes.

To add a keyboard, record the USB IDs reported by Linux and check its LED
addresses, key layout, packet format, and color adjustments on the laptop.
Include sample device files with personal details removed and the expected
packet bytes in tests. The shared vendor and name alone do not establish support.
