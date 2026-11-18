enum DashboardMetric {
  cpuTemperature('CPU temperature'),
  igpuTemperature('iGPU temperature'),
  dgpuTemperature('dGPU temperature'),
  cpuFan('CPU fan speed'),
  gpuFan('GPU fan speed'),
  thirdFan('Fan 3 speed'),
  diskTemperature('Disk temperature'),
  cpuUsage('CPU usage'),
  igpuUsage('iGPU usage'),
  dgpuUsage('dGPU usage'),
  vram('dGPU memory usage'),
  systemTemperature('System temperature');

  const DashboardMetric(this.label);
  final String label;

  static const defaultHidden = {systemTemperature};
}
