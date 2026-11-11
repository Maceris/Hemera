"""
Generates the raw Vulkan bindings in vendor/vulkan from the Vulkan registry, vk.xml.

    python generate.py [path/to/vk.xml]

Without a path, it uses the newest Vulkan SDK's registry it finds (VULKAN_SDK, then C:/VulkanSDK/*).

The output is a direct mapping of the C API, meant to be wrapped by something nicer:

* Enums are `enum #backed_by(u32)`, with negative values (VkResult's errors) written as their 32-bit two's complement.
* Flags are distinct aliases of VkFlags or VkFlags64, and each bit is a constant of its Flags type, so they combine
  with `|` as in C. A FlagBits type is the same type as its Flags.
* Dispatchable handles are distinct aliases of rawptr, non-dispatchable ones of u64, so both can be VK_NULL_HANDLE.
* Pointers in structs are always optional, since structs start zeroed. Parameters follow the registry's `optional`.
* Structs are plain structs, not #scoped, so they can be kept anywhere, dynamic arrays included. A struct passed to a
  command can be a local, but what it points at, directly or through pNext, comes from an allocator such as std's
  memory.Arena (docs/memory.md, Pointers to the Stack).
* sType has its value as the field's default.
* Commands the Vulkan loader exports are #foreign. Every other command is a PFN_ type and a field of
  VulkanInstanceProcs or VulkanDeviceProcs, filled by load_instance_procs or load_device_procs.
* Platform extensions (Win32, Xlib, Wayland, Metal, Android and so on) are all included, on every OS: their types
  from other headers (HWND, Display, wl_surface...) are defined in vulkan_platform.hsc, as opaque structs or aliases
  of what the header makes them. Only the surface commands the loader exports on one OS (Win32's on Windows; Xlib's,
  XCB's and Wayland's on Linux) are #foreign, inside `#if OS == ...`, since linking needs them; every other platform
  command is loaded by name, so it's simply null where the driver doesn't have it.
* Provisional extensions (VK_ENABLE_BETA_EXTENSIONS in C) are included, each of their structs and commands marked
  as such: they can change in a later registry.

The video extensions, whose types come from the video headers (video.xml), are left out, along with anything that
needs them, and so is GGP's platform, whose header was never published.
"""

import glob
import os
import re
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
OUTPUT = os.path.dirname(HERE)

# Extensions the loader exports commands for, on every platform, besides the core versions
LOADER_EXPORTED_EXTENSIONS = {
    "VK_KHR_surface",
    "VK_KHR_swapchain",
    "VK_KHR_display",
    "VK_KHR_display_swapchain",
    "VK_KHR_get_surface_capabilities2",
    "VK_KHR_get_display_properties2",
    "VK_EXT_headless_surface",
}

C_TYPES = {
    "void": "void",
    "char": "u8",
    "float": "f32",
    "double": "f64",
    "int8_t": "i8",
    "int16_t": "i16",
    "int32_t": "i32",
    "int64_t": "i64",
    "uint8_t": "u8",
    "uint16_t": "u16",
    "uint32_t": "u32",
    "uint64_t": "u64",
    "size_t": "usize",
    "int": "i32",
}

# Platform extensions whose commands the loader exports on one OS, which are #foreign there, by Hemera's name for it.
# Checked against vulkan-1.lib (Vulkan SDK 1.3.268) and libvulkan.so.1 (1.4.309).
LOADER_EXPORTED_PLATFORM_EXTENSIONS = {
    "VK_KHR_win32_surface": "Windows",
    "VK_KHR_xlib_surface": "Linux",
    "VK_KHR_xcb_surface": "Linux",
    "VK_KHR_wayland_surface": "Linux",
}

# Types from platform headers, as Hemera declarations: an opaque struct for what C only uses through pointers, and
# otherwise an alias of what the header defines. X11's IDs are `unsigned long`, 64 bits on Linux.
PLATFORM_TYPES = {
    # windows.h
    "HINSTANCE": "alias rawptr",
    "HWND": "alias rawptr",
    "HMONITOR": "alias rawptr",
    "HANDLE": "alias rawptr",
    "DWORD": "alias u32",
    "LPCWSTR": "alias ptr[u16]?",
    "SECURITY_ATTRIBUTES": "struct {\n    nLength : u32,\n    lpSecurityDescriptor : rawptr,\n    bInheritHandle : b32,\n}",
    # X11/Xlib.h and X11/extensions/Xrandr.h
    "Display": "struct {}",
    "VisualID": "alias u64",
    "Window": "alias u64",
    "RROutput": "alias u64",
    # xcb/xcb.h
    "xcb_connection_t": "struct {}",
    "xcb_visualid_t": "alias u32",
    "xcb_window_t": "alias u32",
    # wayland-client.h
    "wl_display": "struct {}",
    "wl_surface": "struct {}",
    # directfb.h
    "IDirectFB": "struct {}",
    "IDirectFBSurface": "struct {}",
    # zircon/types.h
    "zx_handle_t": "alias u32",
    # screen/screen.h (QNX)
    "_screen_context": "struct {}",
    "_screen_window": "struct {}",
    "_screen_buffer": "struct {}",
}

# Which header each group of PLATFORM_TYPES comes from, for the comments in vulkan_platform.hsc
PLATFORM_HEADERS = {
    "HINSTANCE": "windows.h", "Display": "X11/Xlib.h and X11/extensions/Xrandr.h", "xcb_connection_t": "xcb/xcb.h",
    "wl_display": "wayland-client.h", "IDirectFB": "directfb.h", "zx_handle_t": "zircon/types.h",
    "_screen_context": "screen/screen.h (QNX)",
}

# Platform types whose C names Hemera can't use, since a name can't start with an underscore
PLATFORM_TYPE_NAMES = {
    "_screen_context": "screen_context",
    "_screen_window": "screen_window",
    "_screen_buffer": "screen_buffer",
}

# Hemera's keywords, which a field or parameter can't be named
KEYWORDS = set("""
    alias all as auto_cast bit_cast break case cast compute context continue defer distinct else enum false fn for
    from give if import in is_error is_none is_ok is_some loop match mut null or_break or_continue or_else or_return
    package push_context return struct switch true union using void while with
""".split())

# Function pointer types that foreign code gives Hemera, rather than Hemera code foreign code calls back
FOREIGN_FUNCTION_POINTERS = {"PFN_vkVoidFunction", "PFN_vkGetInstanceProcAddrLUNARG"}

HEADER = """package vulkan

// Generated by _generator/generate.py from vk.xml (Vulkan {version}). Don't edit: change the generator and run it again.
"""


def find_registry():
    candidates = []
    if os.environ.get("VULKAN_SDK"):
        candidates.append(os.path.join(os.environ["VULKAN_SDK"], "share", "vulkan", "registry", "vk.xml"))
    candidates += sorted(glob.glob("C:/VulkanSDK/*/share/vulkan/registry/vk.xml"), reverse=True)
    for candidate in candidates:
        if os.path.exists(candidate):
            return candidate
    sys.exit("No vk.xml found: pass its path, or set VULKAN_SDK")


def for_vulkan(element):
    api = element.get("api")
    return api is None or "vulkan" in api.split(",")


def field_name(name):
    return name + "_" if name in KEYWORDS else name


def text_without_comments(element):
    parts = [element.text or ""]
    for child in element:
        if child.tag != "comment":
            parts.append("".join(child.itertext()))
        parts.append(child.tail or "")
    return "".join(parts)


class Declaration:
    """A member or parameter: `const T* const* name[N]:bits`, taken apart."""

    def __init__(self, element):
        self.name = element.find("name").text
        self.type = element.find("type").text
        self.optional = (element.get("optional") or "").split(",")
        self.len = element.get("len") or element.get("altlen")
        self.values = element.get("values")
        # The text around <type> and <name>: `const` before the type, pointers between, arrays and bits after
        before_type, after_type, after = element.text or "", "", ""
        seen_name = False
        for child in element:
            if child.tag == "name":
                seen_name = True
                after += child.tail or ""
            elif child.tag == "type":
                after_type += child.tail or ""
            elif seen_name and child.tag != "comment":
                after += "".join(child.itertext()) + (child.tail or "")
        self.base_const = "const" in before_type or after_type.strip().startswith("const")
        # Whether what each pointer level points at is const, innermost first
        self.pointers = []
        pointee_const = self.base_const
        for match in re.finditer(r"\*(\s*const)?", after_type):
            self.pointers.append(pointee_const)
            pointee_const = match.group(1) is not None
        self.array = re.findall(r"\[([^\]]+)\]", after)
        bits = re.search(r":\s*(\d+)", after)
        self.bits = int(bits.group(1)) if bits else None


class Generator:
    def __init__(self, path):
        self.root = ET.parse(path).getroot()
        self.types = {}
        for t in self.root.find("types"):
            if t.tag == "type" and for_vulkan(t):
                name = t.get("name") or t.find("name").text
                self.types[name] = t
        self.commands = {}
        for c in self.root.find("commands"):
            if not for_vulkan(c):
                continue
            name = c.get("name") or c.find("proto/name").text
            self.commands[name] = c
        self.enum_blocks = {e.get("name"): e for e in self.root.findall("enums")}
        self.version = "?"
        self.header_version = None
        for t in self.root.find("types"):
            if t.get("category") == "define" and for_vulkan(t) and t.find("name") is not None and t.find("name").text == "VK_HEADER_VERSION":
                self.header_version = int(t.find("name").tail.strip())
        # What's required, from each core version and extension included
        self.required_types = set()
        self.required_commands = {}     # name -> whether the loader exports it
        self.command_os = {}            # name -> the OS whose loader exports it, for platform commands
        self.provisional = {}           # type or command name -> the provisional extension it comes from
        self.extension_enums = {}       # enum type -> [(name, value or alias)]
        self.constants = []             # (name, type, value), from API Constants and extensions
        self.dropped = set()
        self.unsupported_types = self.find_unsupported_types()

    def find_unsupported_types(self):
        """Types from other headers (windows.h, the video headers...), which the bindings leave out."""
        result = set()
        for name, t in self.types.items():
            requires = t.get("requires")
            if (t.get("category") is None and requires is not None and requires != "vk_platform" and name not in C_TYPES
                    and name not in PLATFORM_TYPES):
                result.add(name)
        return result

    # Gathering ---------------------------------------------------------------------------------------------------

    def gather(self):
        for feature in self.root.findall("feature"):
            if not for_vulkan(feature):
                continue
            self.version = feature.get("number")
            self.require(feature, None, exported=True)
        for extension in self.root.find("extensions"):
            supported = extension.get("supported", "").split(",")
            if "vulkan" not in supported:
                continue
            name = extension.get("name")
            os_name = LOADER_EXPORTED_PLATFORM_EXTENSIONS.get(name)
            self.require(extension, int(extension.get("number")),
                         exported=name in LOADER_EXPORTED_EXTENSIONS or os_name is not None, os_name=os_name,
                         provisional=name if extension.get("provisional") == "true" else None)
        self.close_over_types()

    def require(self, feature, extension_number, exported, os_name=None, provisional=None):
        for require in feature.findall("require"):
            if not for_vulkan(require):
                continue
            for item in require:
                if item.tag == "type":
                    self.required_types.add(item.get("name"))
                    if provisional is not None:
                        self.provisional.setdefault(item.get("name"), provisional)
                elif item.tag == "command":
                    name = item.get("name")
                    self.required_commands[name] = self.required_commands.get(name, False) or exported
                    if os_name is not None:
                        self.command_os[name] = os_name
                    if provisional is not None:
                        self.provisional.setdefault(name, provisional)
                elif item.tag == "enum" and for_vulkan(item):
                    self.require_enum(item, extension_number)

    def require_enum(self, item, extension_number):
        name = item.get("name")
        extends = item.get("extends")
        if extends is None:
            if item.get("value") is not None or item.get("alias") is not None:
                self.constants.append((name, None, item.get("value"), item.get("alias")))
            return
        if item.get("alias") is not None:
            value = ("alias", item.get("alias"))
        elif item.get("bitpos") is not None:
            value = 1 << int(item.get("bitpos"))
        elif item.get("offset") is not None:
            number = int(item.get("extnumber") or extension_number)
            value = 1000000000 + (number - 1) * 1000 + int(item.get("offset"))
            if item.get("dir") == "-":
                value = -value
        else:
            value = int(item.get("value"), 0)
        self.extension_enums.setdefault(extends, []).append((name, value))

    def referenced_types(self, name):
        t = self.types.get(name)
        if t is None:
            return []
        result = []
        if t.get("alias"):
            result.append(t.get("alias"))
        for attribute in ("requires", "bitvalues"):
            if t.get(attribute) and t.get(attribute) in self.types:
                result.append(t.get(attribute))
        for member in t.findall("member"):
            if for_vulkan(member):
                result.append(member.find("type").text)
        for child in t.findall("type"):
            result.append(child.text)
        return result

    def close_over_types(self):
        for command in list(self.required_commands):
            for name in self.command_types(command):
                self.required_types.add(name)
        pending = list(self.required_types)
        while pending:
            name = pending.pop()
            for referenced in self.referenced_types(name):
                if referenced not in self.required_types:
                    self.required_types.add(referenced)
                    pending.append(referenced)
        # Leave out what needs a type from another header
        changed = True
        while changed:
            changed = False
            for name in sorted(self.required_types):
                if name in self.dropped:
                    continue
                if name in self.unsupported_types or any(r in self.dropped or r in self.unsupported_types
                                                          for r in self.referenced_types(name)):
                    self.dropped.add(name)
                    changed = True
        for command in list(self.required_commands):
            if any(t in self.dropped or t in self.unsupported_types for t in self.command_types(command)):
                del self.required_commands[command]
                self.dropped.add(command)

    def command_element(self, name):
        c = self.commands[name]
        if c.get("alias"):
            return self.command_element(c.get("alias"))
        return c

    def command_types(self, name):
        c = self.command_element(name)
        types = [c.find("proto/type").text]
        types += [p.find("type").text for p in c.findall("param") if for_vulkan(p)]
        return types

    def wanted(self, name):
        return name in self.required_types and name not in self.dropped

    def category(self, name):
        t = self.types.get(name)
        return t.get("category") if t is not None else None

    # Types -------------------------------------------------------------------------------------------------------

    def base_type(self, name):
        if name in C_TYPES:
            return C_TYPES[name]
        return PLATFORM_TYPE_NAMES.get(name, name)

    def type_of(self, decl, optional_pointer):
        base = self.base_type(decl.type)
        result = base
        if decl.pointers:
            for level, pointee_const in enumerate(decl.pointers):
                if level == 0 and base == "void":
                    result = "rawptr"
                elif level == 0 and base == "u8" and pointee_const:
                    result = "cstring"
                else:
                    result = f"ptr[{result}]" if pointee_const else f"ptr[mut {result}]"
            # A rawptr can be null already, and its optional would have a tag
            if optional_pointer and result != "rawptr":
                result += "?"
        for size in reversed(decl.array):
            result = f"{result}[{size.strip()}]"
        return result

    # Output ------------------------------------------------------------------------------------------------------

    def write(self, file_name, body):
        text = HEADER.format(version=f"{self.version}.{self.header_version}") + "\n" + body.rstrip() + "\n"
        with open(os.path.join(OUTPUT, file_name), "w", newline="\n") as f:
            f.write(text)

    def constant_value(self, value, type_name):
        value = value.strip()
        if value.startswith('"'):
            return "cstring", value
        match = re.fullmatch(r"\(~(\d+)(U|ULL)\)", value)
        if match:
            bits = 64 if match.group(2) == "ULL" else 32
            return ("u64" if bits == 64 else "u32"), hex(((1 << bits) - 1) ^ int(match.group(1)))
        if value.endswith("F"):
            return "f32", value[:-1]
        if type_name is not None:
            return C_TYPES.get(type_name, "u32"), value
        return "u32", value

    def generate_constants(self):
        lines = []
        v = self.header_version
        lines.append(f"VK_HEADER_VERSION : u32 : {v}")
        lines.append(f"VK_HEADER_VERSION_COMPLETE : u32 : {hex((1 << 22) | (3 << 12) | v)}")
        for minor in range(0, 4):
            lines.append(f"VK_API_VERSION_1_{minor} : u32 : {hex((1 << 22) | (minor << 12))}")
        lines.append("")
        lines.append("// API Constants")
        for e in self.enum_blocks["API Constants"]:
            if e.tag != "enum":
                continue
            if e.get("alias"):
                lines.append(f"{e.get('name')} :: {e.get('alias')}")
            else:
                type_name, value = self.constant_value(e.get("value"), e.get("type"))
                lines.append(f"{e.get('name')} : {type_name} : {value}")
        lines.append("")
        lines.append("// Extensions' names and versions")
        seen = set()
        for name, type_name, value, alias in self.constants:
            if name in seen or name in self.enum_names_api_constants():
                continue
            seen.add(name)
            if alias is not None:
                lines.append(f"{name} :: {alias}")
            else:
                type_name, value = self.constant_value(value, None)
                lines.append(f"{name} : {type_name} : {value}")
        self.write("vulkan_constants.hsc", "\n".join(lines))

    def enum_names_api_constants(self):
        if not hasattr(self, "_api_constant_names"):
            self._api_constant_names = {e.get("name") for e in self.enum_blocks["API Constants"] if e.tag == "enum"}
        return self._api_constant_names

    def enum_members(self, name):
        """An enum's members in order, as (name, value), with aliases resolved to values."""
        members = []
        block = self.enum_blocks.get(name)
        if block is not None:
            for e in block:
                if e.tag != "enum" or not for_vulkan(e):
                    continue
                if e.get("alias"):
                    members.append((e.get("name"), ("alias", e.get("alias"))))
                elif e.get("bitpos") is not None:
                    members.append((e.get("name"), 1 << int(e.get("bitpos"))))
                else:
                    members.append((e.get("name"), int(e.get("value"), 0)))
        members += self.extension_enums.get(name, [])
        values = {}
        order = []
        for member_name, value in members:
            if member_name not in values:
                values[member_name] = value
                order.append(member_name)
        result = []
        for member_name in order:
            value = values[member_name]
            while isinstance(value, tuple):
                value = values[value[1]]
            result.append((member_name, value))
        return result

    def generate_enums(self):
        lines = []
        for name in sorted(self.required_types):
            t = self.types.get(name)
            if not self.wanted(name) or self.category(name) != "enum" or t.get("alias"):
                continue
            block = self.enum_blocks.get(name)
            if block is not None and block.get("type") == "bitmask":
                continue
            lines.append(f"{name} :: enum #backed_by(u32) {{")
            for member, value in self.enum_members(name):
                if value < 0:
                    lines.append(f"    {member} = {hex(value & 0xFFFFFFFF)}, // {value}")
                else:
                    lines.append(f"    {member} = {value},")
            lines.append("}")
            lines.append("")
        for name in sorted(self.required_types):
            t = self.types.get(name)
            if self.wanted(name) and self.category(name) == "enum" and t.get("alias"):
                lines.append(f"{name} :: {t.get('alias')}")
        self.write("vulkan_enums.hsc", "\n".join(lines))

    def generate_types(self):
        lines = ["// Base types", "VkFlags :: distinct alias u32", "VkFlags64 :: distinct alias u64",
                 "VkBool32 :: alias b32"]
        for name in sorted(self.required_types):
            t = self.types[name] if name in self.types else None
            if t is None or not self.wanted(name) or self.category(name) != "basetype":
                continue
            if name in ("VkFlags", "VkFlags64", "VkBool32"):
                continue
            inner = t.find("type")
            if inner is None and (t.text or "").rstrip().endswith("*"):
                # A platform's pointer type outside Objective-C, like `typedef void* MTLDevice_id`
                lines.append(f"{name} :: alias rawptr")
            elif inner is None:
                # Used only through pointers, like ANativeWindow and CAMetalLayer
                lines.append(f"{name} :: struct {{}}")
            elif "*" in (inner.tail or ""):
                lines.append(f"{name} :: distinct alias rawptr")
            else:
                lines.append(f"{name} :: distinct alias {self.base_type(inner.text)}")
        lines += ["", "// Handles", "VkHandle :: distinct alias rawptr", "VkNonDispatchableHandle :: distinct alias u64"]
        for name in sorted(self.required_types):
            t = self.types.get(name)
            if not self.wanted(name) or self.category(name) != "handle":
                continue
            if t.get("alias"):
                lines.append(f"{name} :: {t.get('alias')}")
            elif t.find("type").text == "VK_DEFINE_HANDLE":
                lines.append(f"{name} :: distinct alias VkHandle")
            else:
                lines.append(f"{name} :: distinct alias VkNonDispatchableHandle")
        lines += ["", "// Flags"]
        flag_bits_with_flags = set()
        for name in sorted(self.required_types):
            t = self.types.get(name)
            if not self.wanted(name) or self.category(name) != "bitmask":
                continue
            if t.get("alias"):
                lines.append(f"{name} :: {t.get('alias')}")
                continue
            backing = t.find("type").text
            lines.append(f"{name} :: distinct alias {backing}")
            bits = t.get("requires") or t.get("bitvalues")
            if bits:
                lines.append(f"{bits} :: {name}")
                flag_bits_with_flags.add(bits)
        for name in sorted(self.required_types):
            t = self.types.get(name)
            if (self.wanted(name) and self.category(name) == "enum" and not t.get("alias")
                    and self.enum_blocks.get(name) is not None and self.enum_blocks[name].get("type") == "bitmask"
                    and name not in flag_bits_with_flags):
                width = self.enum_blocks[name].get("bitwidth")
                lines.append(f"{name} :: distinct alias {'VkFlags64' if width == '64' else 'VkFlags'}")
        lines += ["", "// Function pointers, which foreign code calls back"]
        for name in sorted(self.required_types):
            if self.wanted(name) and self.category(name) == "funcpointer":
                lines.append(self.function_pointer(name))
        self.write("vulkan_types.hsc", "\n".join(lines))

    def flag_bits_type(self, enum_name):
        """The Flags type an enum of bits belongs to."""
        for name, t in self.types.items():
            if self.category(name) == "bitmask" and (t.get("requires") == enum_name or t.get("bitvalues") == enum_name):
                return name
        return enum_name

    def generate_flags(self):
        lines = []
        for name in sorted(self.required_types):
            t = self.types.get(name)
            block = self.enum_blocks.get(name)
            if (not self.wanted(name) or self.category(name) != "enum" or t.get("alias") or block is None
                    or block.get("type") != "bitmask"):
                continue
            flags = self.flag_bits_type(name)
            lines.append(f"// {name}")
            for member, value in self.enum_members(name):
                lines.append(f"{member} : {flags} : {hex(value)}")
            lines.append("")
        self.write("vulkan_flags.hsc", "\n".join(lines))

    def function_pointer(self, name):
        t = self.types[name]
        text = text_without_comments(t)
        returned = re.match(r"\s*typedef\s+(.*?)\s*\(VKAPI_PTR", text, re.S).group(1)
        parameters = text.split(")(", 1)[1].rsplit(")", 1)[0].strip()
        hemera_parameters = []
        if parameters != "void":
            for parameter in parameters.split(","):
                match = re.match(r"\s*(const\s+)?(\w+)\s*(\*?)\s*(const\s*)?(\*?)\s*(\w+)\s*$", parameter)
                const, base, star1, _, star2, parameter_name = match.groups()
                fake = Declaration.__new__(Declaration)
                fake.type = base
                fake.pointers = []
                fake.array = []
                pointee_const = bool(const)
                for star in (star1, star2):
                    if star:
                        fake.pointers.append(pointee_const)
                        pointee_const = False
                hemera_parameters.append(f"{field_name(parameter_name)}: {self.type_of(fake, optional_pointer=bool(fake.pointers))}")
        result = self.returned_type(returned)
        arrow = "" if result == "void" else f" -> {result}"
        convention = "#calling_convention(.c) #no_context" if name in FOREIGN_FUNCTION_POINTERS else "#calling_convention(.c)"
        return f"{name} :: alias fn({', '.join(hemera_parameters)}){arrow} {convention}"

    def returned_type(self, text):
        text = text.strip()
        if text == "void*":
            return "rawptr"
        return self.base_type(text)

    def generate_structs(self):
        lines = []
        for name in sorted(self.required_types):
            t = self.types.get(name)
            category = self.category(name)
            if not self.wanted(name) or category not in ("struct", "union"):
                continue
            if t.get("alias"):
                lines.append(f"{name} :: {t.get('alias')}")
                lines.append("")
                continue
            lines += self.provisional_comment(name)
            directives = []
            if category == "union":
                directives.append("#union")
            lines.append(f"{name} :: struct{''.join(' ' + d for d in directives)} {{")
            members = [Declaration(m) for m in t.findall("member") if for_vulkan(m)]
            i = 0
            while i < len(members):
                decl = members[i]
                if decl.bits is not None:
                    # C bitfields, which share one u32: the first field's bits are its lowest
                    names, total, layout = [], 0, []
                    while i < len(members) and members[i].bits is not None and total < 32:
                        names.append(members[i].name)
                        layout.append(f"{members[i].name} : {members[i].bits}")
                        total += members[i].bits
                        i += 1
                    lines.append(f"    // Bits, lowest first: {', '.join(layout)}")
                    lines.append(f"    {'_'.join(names)} : u32,")
                    continue
                field_type = self.type_of(decl, optional_pointer=True)
                default = ""
                if decl.name == "sType" and decl.values:
                    default = f" = .{decl.values}"
                lines.append(f"    {field_name(decl.name)} : {field_type}{default},")
                i += 1
            lines.append("}")
            lines.append("")
        self.write("vulkan_structs.hsc", "\n".join(lines))

    def parameters(self, command):
        c = self.command_element(command)
        result = []
        for p in c.findall("param"):
            if not for_vulkan(p):
                continue
            decl = Declaration(p)
            optional = decl.optional[0] == "true" if decl.optional else False
            if decl.array:
                # An array parameter is a pointer to it, as in C
                result.append(f"{field_name(decl.name)}: ptr[{self.type_of(decl, optional_pointer=False)}]")
                continue
            result.append(f"{field_name(decl.name)}: {self.type_of(decl, optional_pointer=optional)}")
        returned = self.base_type(c.find("proto/type").text)
        return result, returned

    def dispatch_level(self, command):
        c = self.command_element(command)
        first = c.find("param/type").text
        if first in ("VkDevice", "VkQueue", "VkCommandBuffer") and command not in ("vkGetDeviceProcAddr",):
            return "device"
        return "instance"

    def provisional_comment(self, name):
        """The line marking a provisional extension's struct or command, or none."""
        extension = self.provisional.get(name)
        if extension is None:
            return []
        return [f"// Provisional ({extension}): it can change in a later registry"]

    def generate_platform_types(self):
        lines = ["// Types from platform headers, which only the platform extensions use"]
        for name, declaration in PLATFORM_TYPES.items():
            if name in PLATFORM_HEADERS:
                lines += ["", f"// {PLATFORM_HEADERS[name]}"]
            if self.wanted(name):
                lines.append(f"{self.base_type(name)} :: {declaration}")
        self.write("vulkan_platform.hsc", "\n".join(lines))

    def generate_commands(self):
        foreign, foreign_by_os, pointers = [], {}, []
        for name in sorted(self.required_commands):
            parameters, returned = self.parameters(name)
            arrow = "" if returned == "void" else f" -> {returned}"
            signature = f"fn({', '.join(parameters)}){arrow}"
            if name in self.command_os:
                foreign_by_os.setdefault(self.command_os[name], []).append(f"{name} #foreign(VULKAN) : {signature} : ---")
            elif self.required_commands[name]:
                foreign.append(f"{name} #foreign(VULKAN) : {signature} : ---")
            else:
                pointers.append((name, self.provisional_comment(name)
                                 + [f"PFN_{name} :: alias {signature} #calling_convention(.c) #no_context"]))
        lines = ["// Commands the Vulkan loader exports", ""] + foreign
        for os_name in sorted(foreign_by_os):
            lines += ["", f"// Surface commands the loader exports on {os_name} only", f"#if OS == .{os_name} {{"]
            lines += [f"    {f}" for f in foreign_by_os[os_name]]
            lines.append("}")
        lines += ["", "// Commands found through vkGetInstanceProcAddr and vkGetDeviceProcAddr", ""]
        lines += [line for _, p in pointers for line in p]
        for level in ("instance", "device"):
            names = [n for n, _ in pointers if self.dispatch_level(n) == level]
            struct = f"Vulkan{level.capitalize()}Procs"
            lines += ["", struct + " :: struct {"]
            lines += [f"    {n} : PFN_{n}?," for n in names]
            lines += ["}", ""]
            handle = "VkInstance" if level == "instance" else "VkDevice"
            get = "vkGetInstanceProcAddr" if level == "instance" else "vkGetDeviceProcAddr"
            lines.append(f"// Finds each of the {level}'s commands the loader doesn't export, leaving those it doesn't have null")
            lines.append(f"load_{level}_procs :: fn({level}: {handle}, procs: ptr[mut {struct}]) {{")
            for n in names:
                lines.append(f'    procs.{n} = bit_cast[PFN_{n}?]({get}({level}, "{n}"))')
            lines.append("}")
        self.write("vulkan_commands.hsc", "\n".join(lines))

    def run(self):
        self.gather()
        self.generate_constants()
        self.generate_enums()
        self.generate_types()
        self.generate_platform_types()
        self.generate_flags()
        self.generate_structs()
        self.generate_commands()
        exported = sum(1 for e in self.required_commands.values() if e)
        print(f"Vulkan {self.version}.{self.header_version}: {len(self.required_commands)} commands "
              f"({exported} foreign, {len(self.required_commands) - exported} loaded), "
              f"{sum(1 for n in self.required_types if self.wanted(n) and self.category(n) in ('struct', 'union'))} structs and unions, "
              f"{len(self.dropped)} types and commands left out")
        dropped_commands = sorted(n for n in self.dropped if n in self.commands)
        if dropped_commands:
            print("Left out: " + ", ".join(dropped_commands))


if __name__ == "__main__":
    Generator(sys.argv[1] if len(sys.argv) > 1 else find_registry()).run()
