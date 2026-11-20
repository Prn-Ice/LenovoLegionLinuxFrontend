#pragma once

// The typed D-Bus contract between the helper and the Flutter runner. The XML lets the client reject unknown methods and
// check argument types before sending them to the privileged side.

namespace legion_control {
constexpr char control_bus_name[] = "io.github.prnice.LegionControl1";
constexpr char control_object_path[] = "/io/github/prnice/LegionControl1";
constexpr char control_xml[] =
    R"(<node><interface name="io.github.prnice.LegionControl1">
      <method name="GetCapabilities"><arg type="u" direction="out"/><arg type="as" direction="out"/></method>
      <method name="Authorize"/>
      <method name="SetFeature"><arg type="s" direction="in"/><arg type="s" direction="in"/></method>
      <method name="SetToggle"><arg type="s" direction="in"/><arg type="b" direction="in"/></method>
      <method name="SetGraphicsMode"><arg type="s" direction="in"/></method>
      <method name="ApplyFanPreset"><arg type="s" direction="in"/></method>
      <method name="ApplyCurrentFanPreset"/>
      <method name="ApplyFanCurve"><arg type="ay" direction="in"/></method>
      <method name="ApplyCustomConservation"><arg type="u" direction="in"/><arg type="u" direction="in"/></method>
      <method name="SetBootLogo"><arg type="ay" direction="in"/></method>
      <method name="RestoreBootLogo"/>
    </interface></node>)";
}  // namespace legion_control
