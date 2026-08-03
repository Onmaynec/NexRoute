using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.ServiceProcess;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace NexRoute.Tray
{
    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            string root = ResolveRoot(args);
            if (HasArgument(args, "--self-test"))
            {
                return RunSelfTest(root);
            }

            bool created;
            using (var mutex = new Mutex(true, BuildMutexName(root), out created))
            {
                if (!created)
                {
                    return 0;
                }

                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                using (var context = new TrayApplicationContext(root))
                {
                    Application.Run(context);
                }
                GC.KeepAlive(mutex);
            }
            return 0;
        }

        private static bool HasArgument(IEnumerable<string> args, string value)
        {
            return args.Any(delegate(string item) { return string.Equals(item, value, StringComparison.OrdinalIgnoreCase); });
        }

        private static string ResolveRoot(string[] args)
        {
            for (int index = 0; index < args.Length - 1; index++)
            {
                if (string.Equals(args[index], "--root", StringComparison.OrdinalIgnoreCase))
                {
                    return Path.GetFullPath(args[index + 1].Trim('"'));
                }
            }

            var executableDirectory = AppDomain.CurrentDomain.BaseDirectory;
            var nativeDirectory = new DirectoryInfo(executableDirectory);
            if (nativeDirectory.Parent != null && nativeDirectory.Parent.Parent != null)
            {
                return nativeDirectory.Parent.Parent.FullName;
            }
            return executableDirectory;
        }

        private static string BuildMutexName(string root)
        {
            using (var sha = SHA256.Create())
            {
                byte[] digest = sha.ComputeHash(Encoding.UTF8.GetBytes(root.ToLowerInvariant()));
                return "Local\\NexRouteTray-" + BitConverter.ToString(digest, 0, 10).Replace("-", string.Empty);
            }
        }

        private static int RunSelfTest(string root)
        {
            var required = new[]
            {
                "nexroute.bat",
                "service.bat",
                Path.Combine(".service", "version.txt")
            };
            var missing = required.Where(delegate(string relative) { return !File.Exists(Path.Combine(root, relative)); }).ToArray();
            string version = "unknown";
            string versionPath = Path.Combine(root, ".service", "version.txt");
            if (File.Exists(versionPath))
            {
                version = File.ReadAllText(versionPath).Trim();
            }
            string json = "{\"ok\":" + (missing.Length == 0 ? "true" : "false") +
                          ",\"root\":\"" + JsonEscape(root) + "\"" +
                          ",\"version\":\"" + JsonEscape(version) + "\"" +
                          ",\"missing\":[" + string.Join(",", missing.Select(delegate(string item) { return "\"" + JsonEscape(item) + "\""; }).ToArray()) + "]}";
            Console.WriteLine(json);
            return missing.Length == 0 ? 0 : 2;
        }

        private static string JsonEscape(string value)
        {
            return (value ?? string.Empty).Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n");
        }
    }

    internal sealed class TrayApplicationContext : ApplicationContext, IDisposable
    {
        private readonly string root;
        private readonly NotifyIcon notifyIcon;
        private readonly ToolStripMenuItem statusItem;
        private readonly ToolStripMenuItem enableItem;
        private readonly ToolStripMenuItem disableItem;
        private readonly ToolStripMenuItem restartItem;
        private readonly Timer timer;
        private readonly HotkeyWindow hotkey;
        private ServiceControllerStatus? lastStatus;
        private bool disposed;

        internal TrayApplicationContext(string rootPath)
        {
            root = Path.GetFullPath(rootPath);
            var menu = new ContextMenuStrip();
            statusItem = new ToolStripMenuItem("Service: checking...");
            statusItem.Enabled = false;
            menu.Items.Add(statusItem);
            menu.Items.Add(new ToolStripSeparator());

            enableItem = new ToolStripMenuItem("Enable NexRoute", null, delegate { RequestServiceAction("Start"); });
            disableItem = new ToolStripMenuItem("Disable NexRoute", null, delegate { RequestServiceAction("Stop"); });
            restartItem = new ToolStripMenuItem("Restart NexRoute", null, delegate { RequestServiceAction("Restart"); });
            menu.Items.Add(enableItem);
            menu.Items.Add(disableItem);
            menu.Items.Add(restartItem);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(new ToolStripMenuItem("Open Control Center", null, delegate { OpenControlCenter(); }));
            menu.Items.Add(new ToolStripMenuItem("Check Update", null, delegate { OpenUpdater(); }));
            menu.Items.Add(new ToolStripMenuItem("Open Logs", null, delegate { OpenLogs(); }));
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(new ToolStripMenuItem("Exit Tray", null, delegate { ExitTray(); }));

            notifyIcon = new NotifyIcon();
            notifyIcon.ContextMenuStrip = menu;
            notifyIcon.Icon = LoadIcon();
            notifyIcon.Text = "NexRoute";
            notifyIcon.Visible = true;
            notifyIcon.DoubleClick += delegate { OpenControlCenter(); };

            hotkey = new HotkeyWindow(ToggleService);
            timer = new Timer();
            timer.Interval = 3000;
            timer.Tick += delegate { RefreshStatus(true); };
            timer.Start();
            RefreshStatus(false);
            ShowNotification("NexRoute", "Native tray controller started. Ctrl+Alt+N toggles the service.", ToolTipIcon.Info);
        }

        private Icon LoadIcon()
        {
            string iconPath = Path.Combine(root, ".service", "nexroute.ico");
            try
            {
                if (File.Exists(iconPath))
                {
                    return new Icon(iconPath);
                }
            }
            catch { }
            return SystemIcons.Shield;
        }

        private ServiceControllerStatus? GetServiceStatus()
        {
            try
            {
                using (var controller = new ServiceController("zapret"))
                {
                    return controller.Status;
                }
            }
            catch
            {
                return null;
            }
        }

        private void RefreshStatus(bool notifyChanges)
        {
            ServiceControllerStatus? current = GetServiceStatus();
            string label;
            bool running = current.HasValue && current.Value == ServiceControllerStatus.Running;
            if (!current.HasValue)
            {
                label = "Service: not installed";
            }
            else
            {
                label = "Service: " + current.Value.ToString().ToUpperInvariant();
            }
            statusItem.Text = label;
            enableItem.Enabled = !running;
            disableItem.Enabled = running;
            restartItem.Enabled = current.HasValue;
            notifyIcon.Text = Truncate("NexRoute | " + (running ? "RUNNING" : current.HasValue ? current.Value.ToString().ToUpperInvariant() : "NOT INSTALLED"), 63);
            notifyIcon.Icon = running ? SystemIcons.Shield : SystemIcons.Warning;

            if (notifyChanges && lastStatus.HasValue && current.HasValue && lastStatus.Value != current.Value)
            {
                ShowNotification("NexRoute", "Service state changed: " + current.Value, running ? ToolTipIcon.Info : ToolTipIcon.Warning);
            }
            lastStatus = current;
        }

        private static string Truncate(string value, int maximum)
        {
            if (value == null) return string.Empty;
            return value.Length <= maximum ? value : value.Substring(0, maximum);
        }

        private void ToggleService()
        {
            ServiceControllerStatus? status = GetServiceStatus();
            if (status.HasValue && status.Value == ServiceControllerStatus.Running)
            {
                RequestServiceAction("Stop");
            }
            else
            {
                RequestServiceAction("Start");
            }
        }

        private void RequestServiceAction(string action)
        {
            try
            {
                string command;
                if (string.Equals(action, "Restart", StringComparison.OrdinalIgnoreCase))
                {
                    command = "$ErrorActionPreference='Stop'; Stop-Service -Name 'zapret' -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 500; Start-Service -Name 'zapret'";
                }
                else if (string.Equals(action, "Stop", StringComparison.OrdinalIgnoreCase))
                {
                    command = "$ErrorActionPreference='Stop'; Stop-Service -Name 'zapret' -Force; Get-Process -Name 'winws' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue";
                }
                else
                {
                    command = "$ErrorActionPreference='Stop'; Start-Service -Name 'zapret'";
                }

                var start = new ProcessStartInfo();
                start.FileName = "powershell.exe";
                start.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command \"" + command.Replace("\"", "\\\"") + "\"";
                start.UseShellExecute = true;
                start.Verb = "runas";
                start.WorkingDirectory = root;
                Process.Start(start);
                ShowNotification("NexRoute", action + " request sent.", ToolTipIcon.Info);
            }
            catch (Exception exception)
            {
                ShowNotification("NexRoute", exception.Message, ToolTipIcon.Error);
            }
        }

        private void OpenControlCenter()
        {
            StartFile(Path.Combine(root, "nexroute.bat"), string.Empty, false);
        }

        private void OpenUpdater()
        {
            StartFile(Path.Combine(root, "nexroute-update.cmd"), string.Empty, true);
        }

        private void OpenLogs()
        {
            string logs = Path.Combine(root, ".service", "logs");
            Directory.CreateDirectory(logs);
            try
            {
                Process.Start(new ProcessStartInfo("explorer.exe", "\"" + logs + "\"") { UseShellExecute = true });
            }
            catch (Exception exception)
            {
                ShowNotification("NexRoute", exception.Message, ToolTipIcon.Error);
            }
        }

        private void StartFile(string path, string arguments, bool elevate)
        {
            try
            {
                if (!File.Exists(path)) throw new FileNotFoundException("NexRoute command was not found.", path);
                var start = new ProcessStartInfo();
                start.FileName = path;
                start.Arguments = arguments;
                start.WorkingDirectory = root;
                start.UseShellExecute = true;
                if (elevate) start.Verb = "runas";
                Process.Start(start);
            }
            catch (Exception exception)
            {
                ShowNotification("NexRoute", exception.Message, ToolTipIcon.Error);
            }
        }

        private void ShowNotification(string title, string message, ToolTipIcon icon)
        {
            try { notifyIcon.ShowBalloonTip(4000, title, Truncate(message, 240), icon); }
            catch { }
        }

        private void ExitTray()
        {
            Dispose();
            ExitThread();
        }

        public new void Dispose()
        {
            if (disposed) return;
            disposed = true;
            timer.Stop();
            timer.Dispose();
            hotkey.Dispose();
            notifyIcon.Visible = false;
            notifyIcon.Dispose();
            base.Dispose();
        }
    }

    internal sealed class HotkeyWindow : NativeWindow, IDisposable
    {
        private const int WmHotkey = 0x0312;
        private const uint ModAlt = 0x0001;
        private const uint ModControl = 0x0002;
        private const int HotkeyId = 0x4E52;
        private readonly Action action;

        internal HotkeyWindow(Action callback)
        {
            action = callback;
            CreateHandle(new CreateParams());
            RegisterHotKey(Handle, HotkeyId, ModControl | ModAlt, (uint)Keys.N);
        }

        protected override void WndProc(ref Message message)
        {
            if (message.Msg == WmHotkey && message.WParam.ToInt32() == HotkeyId)
            {
                if (action != null) action();
            }
            base.WndProc(ref message);
        }

        public void Dispose()
        {
            try { UnregisterHotKey(Handle, HotkeyId); }
            catch { }
            DestroyHandle();
        }

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern bool UnregisterHotKey(IntPtr window, int id);
    }
}
