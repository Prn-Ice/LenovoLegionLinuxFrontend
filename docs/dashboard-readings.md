# Dashboard readings

Choose readings under **Settings → Dashboard readings**. The app saves each
choice and restores it on launch. Available readings are shown by default,
except **System temperature**, which starts off. Saved choices take precedence
over these defaults. Missing or unsupported readings stay hidden. A measured 0%
remains visible.

Battery status appears in the sidebar and on the Battery page, rather than
repeating it beneath the dashboard usage bars. System temperature comes from
a system/ACPI hwmon sensor, not the CPU temperature reader. Enable it in Settings
if you want that additional reading.

CPU, integrated GPU (iGPU), and discrete GPU (dGPU) usage have separate rows.
The two GPU temperatures also appear separately. A missing GPU reading never
uses a measurement from the other GPU.

## Sources and support

- **CPU usage:** samples of `/proc/stat`, collected by the existing CPU reader.
- **AMD iGPU usage:** the driver's `gpu_busy_percent` in the identified APU's
  DRM device directory. Its temperature comes from the same device's `amdgpu`
  hwmon directory. The app recognizes the kernel's `gpu_metrics` format 2 and 3
  APU layouts. Other layouts, unreadable metrics, and ambiguous multiple-APU
  configurations stay hidden rather than guessing which GPU is integrated.
- **NVIDIA dGPU usage:** `nvidia-smi`, queried by the NVIDIA display controller's
  PCI address. The telemetry reader skips suspended devices and systems with
  multiple NVIDIA display controllers. Missing driver/tool support stays hidden.
- **Intel iGPU and other discrete GPU drivers:** usage is not supported yet.

AMD's firmware computes the usage percentage from GPU activity. We use its
device-wide reading rather than adding process counters, which can omit work
from processes the app cannot inspect. See the kernel's
[AMDGPU sysfs documentation](https://docs.kernel.org/gpu/amdgpu/thermal.html)
and [GPU metrics layouts](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/amd/include/kgd_pp_interface.h).

## Temperature history

Older `gpuTempC` history can contain either GPU's temperature. The GPU
page now uses an explicitly attributed `dgpuTempC` field, so those older samples
do not appear in its temperature chart. Existing records remain readable. CSV
exports append `dgpu_temp_c`; earlier columns retain their meaning and order.

## Check the feature

1. Open the Dashboard on a supported AMD/NVIDIA hybrid laptop. Expect separate
   CPU, iGPU, and dGPU usage rows when their drivers provide readings.
2. Turn off **iGPU usage** in **Settings → Dashboard readings**. Return to the
   Dashboard: that row should be hidden while the other selected readings remain.
3. Close and reopen the app. The iGPU usage row should remain hidden.
4. Re-enable the row. It should return when the driver provides a reading.
5. With the dGPU suspended, expect its unavailable readings to disappear while
   the CPU and iGPU readings continue. A genuine idle reading should display 0%.
