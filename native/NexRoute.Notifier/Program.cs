using System;
using System.Drawing;
using System.Text;
using System.Windows.Forms;

namespace NexRoute.Notifier
{
    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            if (HasFlag(args, "--self-test"))
            {
                string sample = "NexRoute уведомление";
                string encoded = Convert.ToBase64String(Encoding.UTF8.GetBytes(sample));
                string decoded = DecodeBase64(encoded);
                bool ok = string.Equals(sample, decoded, StringComparison.Ordinal);
                Console.WriteLine("{\"ok\":" + (ok ? "true" : "false") + ",\"utf8\":true,\"channel\":\"balloon\"}");
                return ok ? 0 : 2;
            }

            string title = DecodeBase64(GetValue(args, "--title64") ?? string.Empty);
            string message = DecodeBase64(GetValue(args, "--message64") ?? string.Empty);
            string level = (GetValue(args, "--level") ?? "info").ToLowerInvariant();
            int timeout = ParseTimeout(GetValue(args, "--timeout"));
            if (string.IsNullOrWhiteSpace(title)) title = "NexRoute";
            if (string.IsNullOrWhiteSpace(message)) return 3;

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            using (var context = new NotificationContext(title, message, level, timeout))
            {
                Application.Run(context);
            }
            return 0;
        }

        private static bool HasFlag(string[] args, string flag)
        {
            foreach (string value in args)
            {
                if (string.Equals(value, flag, StringComparison.OrdinalIgnoreCase)) return true;
            }
            return false;
        }

        private static string GetValue(string[] args, string name)
        {
            for (int index = 0; index < args.Length - 1; index++)
            {
                if (string.Equals(args[index], name, StringComparison.OrdinalIgnoreCase)) return args[index + 1];
            }
            return null;
        }

        private static string DecodeBase64(string value)
        {
            try { return Encoding.UTF8.GetString(Convert.FromBase64String(value)); }
            catch { return string.Empty; }
        }

        private static int ParseTimeout(string value)
        {
            int parsed;
            if (!int.TryParse(value, out parsed)) parsed = 5000;
            return Math.Max(1000, Math.Min(15000, parsed));
        }
    }

    internal sealed class NotificationContext : ApplicationContext, IDisposable
    {
        private readonly NotifyIcon icon;
        private readonly Timer timer;
        private bool disposed;

        internal NotificationContext(string title, string message, string level, int timeout)
        {
            ToolTipIcon toolTipIcon;
            Icon systemIcon;
            switch (level)
            {
                case "error":
                    toolTipIcon = ToolTipIcon.Error;
                    systemIcon = SystemIcons.Error;
                    break;
                case "warning":
                case "warn":
                    toolTipIcon = ToolTipIcon.Warning;
                    systemIcon = SystemIcons.Warning;
                    break;
                default:
                    toolTipIcon = ToolTipIcon.Info;
                    systemIcon = SystemIcons.Information;
                    break;
            }

            icon = new NotifyIcon();
            icon.Icon = systemIcon;
            icon.Text = Truncate(title, 63);
            icon.Visible = true;
            icon.ShowBalloonTip(timeout, Truncate(title, 63), Truncate(message, 255), toolTipIcon);

            timer = new Timer();
            timer.Interval = timeout + 750;
            timer.Tick += delegate
            {
                Dispose();
                ExitThread();
            };
            timer.Start();
        }

        private static string Truncate(string value, int maximum)
        {
            if (string.IsNullOrEmpty(value)) return string.Empty;
            return value.Length <= maximum ? value : value.Substring(0, maximum);
        }

        public new void Dispose()
        {
            if (disposed) return;
            disposed = true;
            timer.Stop();
            timer.Dispose();
            icon.Visible = false;
            icon.Dispose();
            base.Dispose();
        }
    }
}
