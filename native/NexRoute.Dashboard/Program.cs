using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using System.Windows.Forms.DataVisualization.Charting;

namespace NexRoute.Dashboard
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

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new DashboardForm(root));
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
            DirectoryInfo native = new DirectoryInfo(AppDomain.CurrentDomain.BaseDirectory);
            if (native.Parent != null && native.Parent.Parent != null) return native.Parent.Parent.FullName;
            return native.FullName;
        }

        private static int RunSelfTest(string root)
        {
            string history = Path.Combine(root, ".service", "history", "strategy-lab");
            string versionPath = Path.Combine(root, ".service", "version.txt");
            bool ok = File.Exists(versionPath);
            string version = ok ? File.ReadAllText(versionPath).Trim() : "unknown";
            int runCount = 0;
            int resultCount = 0;
            string error = null;
            try
            {
                var store = new StrategyHistoryStore(history);
                IList<StrategyRun> runs = store.LoadRuns();
                runCount = runs.Count;
                resultCount = runs.Sum(delegate(StrategyRun run) { return run.Results.Count; });
            }
            catch (Exception exception)
            {
                ok = false;
                error = exception.Message;
            }
            Console.WriteLine("{\"ok\":" + (ok ? "true" : "false") +
                              ",\"version\":\"" + Escape(version) + "\"" +
                              ",\"historyDirectory\":\"" + Escape(history) + "\"" +
                              ",\"runCount\":" + runCount.ToString(CultureInfo.InvariantCulture) +
                              ",\"resultCount\":" + resultCount.ToString(CultureInfo.InvariantCulture) +
                              ",\"error\":" + (error == null ? "null" : "\"" + Escape(error) + "\"") + "}");
            return ok ? 0 : 2;
        }

        private static string Escape(string value)
        {
            return (value ?? string.Empty).Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n");
        }
    }

    internal sealed class DashboardForm : Form
    {
        private readonly string root;
        private readonly StrategyHistoryStore historyStore;
        private readonly UiSettingsStore settingsStore;
        private UiSettings settings;
        private IList<StrategyRun> runs;
        private readonly Label serviceValue;
        private readonly Label runValue;
        private readonly Label bestValue;
        private readonly Label updatedValue;
        private ComboBox metricSelector;
        private ComboBox strategySelector;
        private ComboBox themeSelector;
        private ComboBox accentSelector;
        private Chart chart;
        private DataGridView grid;
        private readonly Button refreshButton;
        private Button resetZoomButton;
        private readonly Timer statusTimer;
        private readonly ToolTip toolTip;

        internal DashboardForm(string rootPath)
        {
            root = Path.GetFullPath(rootPath);
            historyStore = new StrategyHistoryStore(Path.Combine(root, ".service", "history", "strategy-lab"));
            settingsStore = new UiSettingsStore(Path.Combine(root, ".service", "ui-settings.json"));
            settings = settingsStore.Load();
            runs = new List<StrategyRun>();

            Text = "NexRoute Dashboard";
            MinimumSize = new Size(900, 620);
            Size = new Size(1120, 760);
            StartPosition = FormStartPosition.CenterScreen;
            Font = new Font("Segoe UI", 9F, FontStyle.Regular, GraphicsUnit.Point);
            Icon = LoadIcon();

            var header = new TableLayoutPanel();
            header.Dock = DockStyle.Top;
            header.Height = 96;
            header.Padding = new Padding(16, 12, 16, 8);
            header.ColumnCount = 5;
            header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 25));
            header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 25));
            header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 25));
            header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 25));
            header.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 130));
            serviceValue = AddStatusCard(header, "SERVICE", 0);
            runValue = AddStatusCard(header, "RUNS", 1);
            bestValue = AddStatusCard(header, "BEST STRATEGY", 2);
            updatedValue = AddStatusCard(header, "UPDATED", 3);
            refreshButton = new Button { Text = "Refresh", Dock = DockStyle.Fill, Margin = new Padding(8, 12, 0, 12), FlatStyle = FlatStyle.Flat };
            refreshButton.Click += delegate { ReloadData(); };
            header.Controls.Add(refreshButton, 4, 0);

            var tabs = new TabControl();
            tabs.Dock = DockStyle.Fill;
            tabs.Padding = new Point(18, 6);
            tabs.TabPages.Add(CreateOverviewPage());
            tabs.TabPages.Add(CreateHistoryPage());
            tabs.TabPages.Add(CreateSettingsPage());

            Controls.Add(tabs);
            Controls.Add(header);

            statusTimer = new Timer { Interval = 3000 };
            statusTimer.Tick += delegate { UpdateServiceState(); };
            statusTimer.Start();
            toolTip = new ToolTip { AutoPopDelay = 10000, InitialDelay = 250, ReshowDelay = 100 };

            FormClosed += delegate { statusTimer.Dispose(); toolTip.Dispose(); };
            ApplyTheme();
            ReloadData();
        }

        private Icon LoadIcon()
        {
            string path = Path.Combine(root, ".service", "nexroute.ico");
            try { if (File.Exists(path)) return new Icon(path); }
            catch { }
            return SystemIcons.Shield;
        }

        private Label AddStatusCard(TableLayoutPanel parent, string title, int column)
        {
            var panel = new Panel { Dock = DockStyle.Fill, Margin = new Padding(column == 0 ? 0 : 8, 0, 0, 0), Padding = new Padding(12, 8, 12, 8) };
            var caption = new Label { Text = title, Dock = DockStyle.Top, Height = 18, Font = new Font(Font, FontStyle.Bold) };
            var value = new Label { Text = "—", Dock = DockStyle.Fill, Font = new Font("Segoe UI Semibold", 13F), AutoEllipsis = true, TextAlign = ContentAlignment.MiddleLeft };
            panel.Controls.Add(value);
            panel.Controls.Add(caption);
            parent.Controls.Add(panel, column, 0);
            return value;
        }

        private TabPage CreateOverviewPage()
        {
            var page = new TabPage("Overview") { Padding = new Padding(12) };
            var rootPanel = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 2 };
            rootPanel.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));
            rootPanel.RowStyles.Add(new RowStyle(SizeType.Percent, 100));

            var toolbar = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.LeftToRight, WrapContents = false, Padding = new Padding(0, 7, 0, 5) };
            toolbar.Controls.Add(new Label { Text = "Metric", AutoSize = true, Margin = new Padding(0, 7, 6, 0) });
            metricSelector = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 180 };
            metricSelector.Items.AddRange(new object[] { "Score", "Download Mbps", "Jitter ms", "Packet loss %", "HTTP latency ms" });
            metricSelector.SelectedIndex = 0;
            metricSelector.SelectedIndexChanged += delegate { RenderChart(); };
            toolbar.Controls.Add(metricSelector);
            toolbar.Controls.Add(new Label { Text = "Strategy", AutoSize = true, Margin = new Padding(18, 7, 6, 0) });
            strategySelector = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 260 };
            strategySelector.SelectedIndexChanged += delegate { RenderChart(); };
            toolbar.Controls.Add(strategySelector);
            resetZoomButton = new Button { Text = "Reset zoom", AutoSize = true, Margin = new Padding(18, 0, 0, 0), FlatStyle = FlatStyle.Flat };
            resetZoomButton.Click += delegate { ResetChartZoom(); };
            toolbar.Controls.Add(resetZoomButton);

            chart = new Chart { Dock = DockStyle.Fill, BorderlineDashStyle = ChartDashStyle.Solid, BorderlineWidth = 1, AntiAliasing = AntiAliasingStyles.All };
            var area = new ChartArea("history");
            area.AxisX.LabelStyle.Format = "MM-dd HH:mm";
            area.AxisX.MajorGrid.LineDashStyle = ChartDashStyle.Dot;
            area.AxisY.MajorGrid.LineDashStyle = ChartDashStyle.Dot;
            area.CursorX.IsUserEnabled = true;
            area.CursorX.IsUserSelectionEnabled = true;
            area.AxisX.ScaleView.Zoomable = true;
            area.CursorY.IsUserEnabled = true;
            area.CursorY.IsUserSelectionEnabled = true;
            area.AxisY.ScaleView.Zoomable = true;
            chart.ChartAreas.Add(area);
            chart.Legends.Add(new Legend("legend") { Docking = Docking.Top });
            chart.MouseWheel += ChartMouseWheel;
            chart.DoubleClick += delegate { ResetChartZoom(); };
            chart.GetToolTipText += ChartToolTip;

            rootPanel.Controls.Add(toolbar, 0, 0);
            rootPanel.Controls.Add(chart, 0, 1);
            page.Controls.Add(rootPanel);
            return page;
        }

        private TabPage CreateHistoryPage()
        {
            var page = new TabPage("History") { Padding = new Padding(12) };
            grid = new DataGridView();
            grid.Dock = DockStyle.Fill;
            grid.ReadOnly = true;
            grid.AllowUserToAddRows = false;
            grid.AllowUserToDeleteRows = false;
            grid.AllowUserToOrderColumns = true;
            grid.AutoGenerateColumns = false;
            grid.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;
            grid.SelectionMode = DataGridViewSelectionMode.FullRowSelect;
            grid.MultiSelect = false;
            grid.RowHeadersVisible = false;
            AddGridColumn("CreatedUtc", "Run", 105);
            AddGridColumn("Network", "Network", 100);
            AddGridColumn("Strategy", "Strategy", 150);
            AddGridColumn("Score", "Score", 70, "N2");
            AddGridColumn("DownloadMbps", "Mbps", 75, "N2");
            AddGridColumn("JitterMs", "Jitter", 70, "N1");
            AddGridColumn("PacketLossPercent", "Loss %", 70, "N1");
            AddGridColumn("AvailabilityPercent", "Avail. %", 80, "N1");
            AddGridColumn("YoutubeReady", "YouTube", 70);
            AddGridColumn("DiscordReady", "Discord", 70);
            AddGridColumn("TelegramReady", "Telegram", 70);
            page.Controls.Add(grid);
            return page;
        }

        private void AddGridColumn(string property, string title, float fillWeight, string format = null)
        {
            var column = new DataGridViewTextBoxColumn { DataPropertyName = property, HeaderText = title, FillWeight = fillWeight, SortMode = DataGridViewColumnSortMode.Automatic };
            if (!string.IsNullOrEmpty(format)) column.DefaultCellStyle.Format = format;
            grid.Columns.Add(column);
        }

        private TabPage CreateSettingsPage()
        {
            var page = new TabPage("Appearance") { Padding = new Padding(24) };
            var layout = new TableLayoutPanel { Dock = DockStyle.Top, Height = 170, ColumnCount = 2, RowCount = 4 };
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 180));
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 260));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 42));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 42));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 42));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 42));
            layout.Controls.Add(new Label { Text = "Theme", Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft }, 0, 0);
            themeSelector = new ComboBox { Dock = DockStyle.Fill, DropDownStyle = ComboBoxStyle.DropDownList };
            themeSelector.Items.AddRange(new object[] { "System", "Light", "Dark" });
            themeSelector.SelectedItem = settings.Theme;
            themeSelector.SelectedIndexChanged += delegate
            {
                if (themeSelector.SelectedItem == null) return;
                settings.Theme = themeSelector.SelectedItem.ToString();
                settingsStore.Save(settings);
                ApplyTheme();
            };
            layout.Controls.Add(themeSelector, 1, 0);
            layout.Controls.Add(new Label { Text = "Accent color", Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft }, 0, 1);
            accentSelector = new ComboBox { Dock = DockStyle.Fill, DropDownStyle = ComboBoxStyle.DropDownList };
            accentSelector.Items.AddRange(ThemePalette.AccentNames.Cast<object>().ToArray());
            accentSelector.SelectedItem = settings.Accent;
            accentSelector.SelectedIndexChanged += delegate
            {
                if (accentSelector.SelectedItem == null) return;
                settings.Accent = accentSelector.SelectedItem.ToString();
                settingsStore.Save(settings);
                ApplyTheme();
            };
            layout.Controls.Add(accentSelector, 1, 1);
            layout.Controls.Add(new Label { Text = "Chart controls", Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft }, 0, 2);
            layout.Controls.Add(new Label { Text = "Mouse wheel: zoom · Drag: select · Double-click: reset", Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft, AutoSize = false }, 1, 2);
            layout.Controls.Add(new Label { Text = "Data source", Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft }, 0, 3);
            layout.Controls.Add(new Label { Text = Path.Combine(".service", "history", "strategy-lab"), Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft, AutoEllipsis = true }, 1, 3);
            page.Controls.Add(layout);
            return page;
        }

        private void ReloadData()
        {
            try
            {
                runs = historyStore.LoadRuns();
                IList<StrategyPoint> points = Flatten(runs);
                grid.DataSource = points.ToList();
                string selected = strategySelector.SelectedItem == null ? "All strategies" : strategySelector.SelectedItem.ToString();
                string[] strategies = points.Select(delegate(StrategyPoint point) { return point.Strategy; }).Where(delegate(string value) { return !string.IsNullOrEmpty(value); }).Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(delegate(string value) { return value; }).ToArray();
                strategySelector.BeginUpdate();
                strategySelector.Items.Clear();
                strategySelector.Items.Add("All strategies");
                strategySelector.Items.AddRange(strategies.Cast<object>().ToArray());
                int index = strategySelector.Items.IndexOf(selected);
                strategySelector.SelectedIndex = index >= 0 ? index : 0;
                strategySelector.EndUpdate();
                runValue.Text = runs.Count.ToString(CultureInfo.InvariantCulture);
                StrategyPoint best = points.OrderByDescending(delegate(StrategyPoint point) { return point.Score; }).FirstOrDefault();
                bestValue.Text = best == null ? "—" : best.Strategy + " · " + best.Score.ToString("N2", CultureInfo.InvariantCulture);
                updatedValue.Text = runs.Count == 0 ? "—" : runs.Max(delegate(StrategyRun run) { return run.CreatedUtc; }).ToLocalTime().ToString("g");
                RenderChart();
            }
            catch (Exception exception)
            {
                MessageBox.Show(this, exception.Message, "NexRoute Dashboard", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            UpdateServiceState();
        }

        private static IList<StrategyPoint> Flatten(IEnumerable<StrategyRun> input)
        {
            var points = new List<StrategyPoint>();
            foreach (StrategyRun run in input)
            {
                foreach (StrategyPoint source in run.Results)
                {
                    source.CreatedUtc = run.CreatedUtc;
                    source.Network = run.Network;
                    points.Add(source);
                }
            }
            return points.OrderByDescending(delegate(StrategyPoint point) { return point.CreatedUtc; }).ThenByDescending(delegate(StrategyPoint point) { return point.Score; }).ToList();
        }

        private void RenderChart()
        {
            if (chart == null || metricSelector == null || strategySelector == null) return;
            string metric = metricSelector.SelectedItem == null ? "Score" : metricSelector.SelectedItem.ToString();
            string selected = strategySelector.SelectedItem == null ? "All strategies" : strategySelector.SelectedItem.ToString();
            IList<StrategyPoint> points = Flatten(runs).OrderBy(delegate(StrategyPoint point) { return point.CreatedUtc; }).ToList();
            if (!string.Equals(selected, "All strategies", StringComparison.OrdinalIgnoreCase))
            {
                points = points.Where(delegate(StrategyPoint point) { return string.Equals(point.Strategy, selected, StringComparison.OrdinalIgnoreCase); }).ToList();
            }
            chart.Series.Clear();
            foreach (IGrouping<string, StrategyPoint> group in points.GroupBy(delegate(StrategyPoint point) { return point.Strategy ?? "Unknown"; }, StringComparer.OrdinalIgnoreCase))
            {
                var series = new Series(group.Key) { ChartType = SeriesChartType.Line, BorderWidth = 3, XValueType = ChartValueType.DateTime, YValueType = ChartValueType.Double, MarkerStyle = MarkerStyle.Circle, MarkerSize = 6, ToolTip = "#SERIESNAME\n#VALX{g}\n#VALY{N2}" };
                foreach (StrategyPoint point in group)
                {
                    int pointIndex = series.Points.AddXY(point.CreatedUtc.ToOADate(), MetricValue(point, metric));
                    series.Points[pointIndex].Tag = point;
                }
                chart.Series.Add(series);
            }
            ChartArea area = chart.ChartAreas[0];
            area.AxisY.Title = metric;
            area.AxisX.Title = "Strategy Lab run";
            ResetChartZoom();
            ApplyChartColors();
        }

        private static double MetricValue(StrategyPoint point, string metric)
        {
            switch (metric)
            {
                case "Download Mbps": return point.DownloadMbps;
                case "Jitter ms": return point.JitterMs;
                case "Packet loss %": return point.PacketLossPercent;
                case "HTTP latency ms": return point.HttpLatencyMs;
                default: return point.Score;
            }
        }

        private void ChartMouseWheel(object sender, MouseEventArgs e)
        {
            try
            {
                ChartArea area = chart.ChartAreas[0];
                double x = area.AxisX.PixelPositionToValue(e.Location.X);
                double y = area.AxisY.PixelPositionToValue(e.Location.Y);
                if (e.Delta > 0)
                {
                    double xSize = Math.Max((area.AxisX.Maximum - area.AxisX.Minimum) / 2.0, 1.0 / 1440.0);
                    double ySize = Math.Max((area.AxisY.Maximum - area.AxisY.Minimum) / 2.0, 0.01);
                    area.AxisX.ScaleView.Zoom(x - xSize / 2.0, x + xSize / 2.0);
                    area.AxisY.ScaleView.Zoom(y - ySize / 2.0, y + ySize / 2.0);
                }
                else
                {
                    area.AxisX.ScaleView.ZoomReset();
                    area.AxisY.ScaleView.ZoomReset();
                }
            }
            catch { }
        }

        private void ResetChartZoom()
        {
            if (chart == null || chart.ChartAreas.Count == 0) return;
            chart.ChartAreas[0].AxisX.ScaleView.ZoomReset(0);
            chart.ChartAreas[0].AxisY.ScaleView.ZoomReset(0);
        }

        private void ChartToolTip(object sender, ToolTipEventArgs e)
        {
            if (e.HitTestResult == null || e.HitTestResult.ChartElementType != ChartElementType.DataPoint) return;
            var point = e.HitTestResult.Object as DataPoint;
            var model = point == null ? null : point.Tag as StrategyPoint;
            if (model == null) return;
            e.Text = model.Strategy + Environment.NewLine +
                     model.CreatedUtc.ToLocalTime().ToString("g") + Environment.NewLine +
                     "Score " + model.Score.ToString("N2") + " · " + model.DownloadMbps.ToString("N2") + " Mbps" + Environment.NewLine +
                     "Jitter " + model.JitterMs.ToString("N1") + " ms · Loss " + model.PacketLossPercent.ToString("N1") + "%";
        }

        private void UpdateServiceState()
        {
            string statePath = Path.Combine(root, ".service", "worker-state.json");
            if (File.Exists(statePath))
            {
                serviceValue.Text = "PER-SERVICE WORKERS";
                serviceValue.ForeColor = ThemePalette.Accent(settings.Accent);
                return;
            }
            try
            {
                using (var service = new System.ServiceProcess.ServiceController("zapret"))
                {
                    serviceValue.Text = service.Status.ToString().ToUpperInvariant();
                    serviceValue.ForeColor = service.Status == System.ServiceProcess.ServiceControllerStatus.Running ? Color.FromArgb(46, 160, 67) : Color.FromArgb(210, 153, 34);
                }
            }
            catch
            {
                serviceValue.Text = "NOT INSTALLED";
                serviceValue.ForeColor = Color.FromArgb(218, 54, 51);
            }
        }

        private void ApplyTheme()
        {
            ThemeColors colors = ThemePalette.Resolve(settings);
            ApplyControlTheme(this, colors);
            refreshButton.BackColor = colors.Accent;
            refreshButton.ForeColor = ThemePalette.Contrast(colors.Accent);
            resetZoomButton.BackColor = colors.Control;
            resetZoomButton.ForeColor = colors.Foreground;
            grid.BackgroundColor = colors.Background;
            grid.GridColor = colors.Border;
            grid.DefaultCellStyle.BackColor = colors.Control;
            grid.DefaultCellStyle.ForeColor = colors.Foreground;
            grid.DefaultCellStyle.SelectionBackColor = colors.Accent;
            grid.DefaultCellStyle.SelectionForeColor = ThemePalette.Contrast(colors.Accent);
            grid.ColumnHeadersDefaultCellStyle.BackColor = colors.Panel;
            grid.ColumnHeadersDefaultCellStyle.ForeColor = colors.Foreground;
            grid.EnableHeadersVisualStyles = false;
            ApplyChartColors();
            Invalidate(true);
        }

        private static void ApplyControlTheme(Control control, ThemeColors colors)
        {
            if (control is TabPage || control is Panel || control is TableLayoutPanel || control is FlowLayoutPanel || control is Form)
            {
                control.BackColor = colors.Background;
                control.ForeColor = colors.Foreground;
            }
            else if (control is Button)
            {
                control.BackColor = colors.Control;
                control.ForeColor = colors.Foreground;
            }
            else if (control is ComboBox || control is Label)
            {
                control.BackColor = colors.Background;
                control.ForeColor = colors.Foreground;
            }
            foreach (Control child in control.Controls) ApplyControlTheme(child, colors);
        }

        private void ApplyChartColors()
        {
            if (chart == null || chart.ChartAreas.Count == 0) return;
            ThemeColors colors = ThemePalette.Resolve(settings);
            chart.BackColor = colors.Background;
            chart.BorderlineColor = colors.Border;
            ChartArea area = chart.ChartAreas[0];
            area.BackColor = colors.Control;
            area.AxisX.LineColor = colors.Border;
            area.AxisY.LineColor = colors.Border;
            area.AxisX.LabelStyle.ForeColor = colors.Foreground;
            area.AxisY.LabelStyle.ForeColor = colors.Foreground;
            area.AxisX.TitleForeColor = colors.Foreground;
            area.AxisY.TitleForeColor = colors.Foreground;
            area.AxisX.MajorGrid.LineColor = colors.Grid;
            area.AxisY.MajorGrid.LineColor = colors.Grid;
            if (chart.Legends.Count > 0)
            {
                chart.Legends[0].BackColor = colors.Background;
                chart.Legends[0].ForeColor = colors.Foreground;
            }
            Color[] palette = ThemePalette.Series(colors.Accent);
            for (int index = 0; index < chart.Series.Count; index++) chart.Series[index].Color = palette[index % palette.Length];
        }
    }

    internal sealed class StrategyHistoryStore
    {
        private readonly string directory;
        private readonly JavaScriptSerializer serializer;

        internal StrategyHistoryStore(string historyDirectory)
        {
            directory = Path.GetFullPath(historyDirectory);
            serializer = new JavaScriptSerializer { MaxJsonLength = 32 * 1024 * 1024, RecursionLimit = 100 };
        }

        internal IList<StrategyRun> LoadRuns()
        {
            if (!Directory.Exists(directory)) return new List<StrategyRun>();
            var runs = new List<StrategyRun>();
            foreach (string file in Directory.GetFiles(directory, "*.json", SearchOption.TopDirectoryOnly).OrderBy(delegate(string path) { return path; }))
            {
                string json = File.ReadAllText(file, Encoding.UTF8);
                object parsed = serializer.DeserializeObject(json);
                var document = parsed as Dictionary<string, object>;
                if (document == null) throw new InvalidDataException("Strategy Lab file is not a JSON object: " + file);
                int schema = ConvertEx.Int(document, "schemaVersion", 0);
                if (schema < 2 || schema > 3) throw new InvalidDataException("Unsupported Strategy Lab schema in " + file + ": " + schema.ToString(CultureInfo.InvariantCulture));
                var run = new StrategyRun();
                run.SourcePath = file;
                run.CreatedUtc = ConvertEx.Date(document, "createdUtc", File.GetLastWriteTimeUtc(file));
                run.Network = ConvertEx.String(document, "network", "unknown");
                object resultsValue;
                if (document.TryGetValue("results", out resultsValue))
                {
                    object[] array = resultsValue as object[];
                    if (array != null)
                    {
                        foreach (object item in array)
                        {
                            var result = item as Dictionary<string, object>;
                            if (result == null) continue;
                            run.Results.Add(new StrategyPoint
                            {
                                Strategy = ConvertEx.String(result, "strategy", "unknown"),
                                Score = ConvertEx.Double(result, "score", 0),
                                DownloadMbps = ConvertEx.Double(result, "measuredDownloadMbps", ConvertEx.Double(result, "peakDownloadMbps", 0)),
                                JitterMs = ConvertEx.Double(result, "averageJitterMs", 0),
                                PacketLossPercent = ConvertEx.Double(result, "averagePacketLossPercent", 0),
                                HttpLatencyMs = ConvertEx.Double(result, "averageHttpLatencyMs", 0),
                                AvailabilityPercent = ConvertEx.Double(result, "availabilityPercent", 0),
                                YoutubeReady = ConvertEx.Bool(result, "youtubePlaybackReady", false),
                                DiscordReady = ConvertEx.Bool(result, "discordRealtimeTransportReady", false),
                                TelegramReady = ConvertEx.Bool(result, "telegramRealtimeTransportReady", false)
                            });
                        }
                    }
                }
                runs.Add(run);
            }
            return runs.OrderBy(delegate(StrategyRun run) { return run.CreatedUtc; }).ToList();
        }
    }

    internal sealed class StrategyRun
    {
        internal StrategyRun() { Results = new List<StrategyPoint>(); }
        public string SourcePath { get; set; }
        public DateTime CreatedUtc { get; set; }
        public string Network { get; set; }
        public List<StrategyPoint> Results { get; private set; }
    }

    internal sealed class StrategyPoint
    {
        public DateTime CreatedUtc { get; set; }
        public string Network { get; set; }
        public string Strategy { get; set; }
        public double Score { get; set; }
        public double DownloadMbps { get; set; }
        public double JitterMs { get; set; }
        public double PacketLossPercent { get; set; }
        public double HttpLatencyMs { get; set; }
        public double AvailabilityPercent { get; set; }
        public bool YoutubeReady { get; set; }
        public bool DiscordReady { get; set; }
        public bool TelegramReady { get; set; }
    }

    internal sealed class UiSettingsStore
    {
        private readonly string path;
        private readonly JavaScriptSerializer serializer = new JavaScriptSerializer();
        internal UiSettingsStore(string settingsPath) { path = Path.GetFullPath(settingsPath); }

        internal UiSettings Load()
        {
            try
            {
                if (!File.Exists(path)) return new UiSettings();
                var document = serializer.Deserialize<UiSettings>(File.ReadAllText(path, Encoding.UTF8));
                return document ?? new UiSettings();
            }
            catch { return new UiSettings(); }
        }

        internal void Save(UiSettings settings)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            string temporary = path + ".tmp-" + Guid.NewGuid().ToString("N");
            File.WriteAllText(temporary, serializer.Serialize(settings) + Environment.NewLine, new UTF8Encoding(false));
            if (File.Exists(path)) File.Delete(path);
            File.Move(temporary, path);
        }
    }

    public sealed class UiSettings
    {
        public UiSettings() { Theme = "System"; Accent = "Cyan"; }
        public string Theme { get; set; }
        public string Accent { get; set; }
    }

    internal sealed class ThemeColors
    {
        internal Color Background;
        internal Color Panel;
        internal Color Control;
        internal Color Foreground;
        internal Color Muted;
        internal Color Border;
        internal Color Grid;
        internal Color Accent;
    }

    internal static class ThemePalette
    {
        internal static readonly string[] AccentNames = { "Cyan", "Blue", "Purple", "Green", "Orange", "Red" };

        internal static ThemeColors Resolve(UiSettings settings)
        {
            string theme = settings == null ? "System" : settings.Theme ?? "System";
            bool dark = string.Equals(theme, "Dark", StringComparison.OrdinalIgnoreCase) ||
                        (string.Equals(theme, "System", StringComparison.OrdinalIgnoreCase) && IsSystemDark());
            return dark
                ? new ThemeColors { Background = Color.FromArgb(18, 22, 28), Panel = Color.FromArgb(25, 31, 40), Control = Color.FromArgb(31, 38, 49), Foreground = Color.FromArgb(238, 242, 248), Muted = Color.FromArgb(156, 166, 181), Border = Color.FromArgb(57, 68, 84), Grid = Color.FromArgb(48, 57, 70), Accent = Accent(settings == null ? null : settings.Accent) }
                : new ThemeColors { Background = Color.FromArgb(247, 249, 252), Panel = Color.White, Control = Color.White, Foreground = Color.FromArgb(25, 31, 41), Muted = Color.FromArgb(91, 101, 115), Border = Color.FromArgb(205, 213, 224), Grid = Color.FromArgb(225, 230, 238), Accent = Accent(settings == null ? null : settings.Accent) };
        }

        internal static Color Accent(string name)
        {
            switch ((name ?? "Cyan").ToLowerInvariant())
            {
                case "blue": return Color.FromArgb(47, 111, 235);
                case "purple": return Color.FromArgb(130, 80, 223);
                case "green": return Color.FromArgb(35, 134, 54);
                case "orange": return Color.FromArgb(215, 105, 0);
                case "red": return Color.FromArgb(207, 34, 46);
                default: return Color.FromArgb(0, 155, 184);
            }
        }

        internal static Color Contrast(Color background)
        {
            double luminance = (0.299 * background.R + 0.587 * background.G + 0.114 * background.B) / 255.0;
            return luminance > 0.58 ? Color.Black : Color.White;
        }

        internal static Color[] Series(Color accent)
        {
            return new[]
            {
                accent,
                Color.FromArgb(47,111,235),
                Color.FromArgb(130,80,223),
                Color.FromArgb(35,134,54),
                Color.FromArgb(215,105,0),
                Color.FromArgb(207,34,46),
                Color.FromArgb(9,105,218),
                Color.FromArgb(191,135,0)
            };
        }

        private static bool IsSystemDark()
        {
            try
            {
                object value = Microsoft.Win32.Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme", 1);
                return Convert.ToInt32(value, CultureInfo.InvariantCulture) == 0;
            }
            catch { return false; }
        }
    }

    internal static class ConvertEx
    {
        internal static string String(Dictionary<string, object> document, string key, string fallback)
        {
            object value;
            return document.TryGetValue(key, out value) && value != null ? Convert.ToString(value, CultureInfo.InvariantCulture) : fallback;
        }

        internal static int Int(Dictionary<string, object> document, string key, int fallback)
        {
            object value;
            if (!document.TryGetValue(key, out value) || value == null) return fallback;
            try { return Convert.ToInt32(value, CultureInfo.InvariantCulture); }
            catch { return fallback; }
        }

        internal static double Double(Dictionary<string, object> document, string key, double fallback)
        {
            object value;
            if (!document.TryGetValue(key, out value) || value == null) return fallback;
            try { return Convert.ToDouble(value, CultureInfo.InvariantCulture); }
            catch { return fallback; }
        }

        internal static bool Bool(Dictionary<string, object> document, string key, bool fallback)
        {
            object value;
            if (!document.TryGetValue(key, out value) || value == null) return fallback;
            try { return Convert.ToBoolean(value, CultureInfo.InvariantCulture); }
            catch { return fallback; }
        }

        internal static DateTime Date(Dictionary<string, object> document, string key, DateTime fallback)
        {
            string value = String(document, key, null);
            DateTime parsed;
            return value != null && DateTime.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out parsed) ? parsed : fallback;
        }
    }
}
