using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace NexRoute.Validation
{
    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            string root = ResolveRoot(args);
            string reportPath = ResolveReportPath(root, args);
            ValidationSnapshot snapshot = ValidationLoader.Load(root, reportPath);
            if (HasArgument(args, "--self-test"))
            {
                return WriteSelfTest(snapshot);
            }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new ValidationForm(root, snapshot));
            return 0;
        }

        private static bool HasArgument(IEnumerable<string> args, string value)
        {
            return args.Any(delegate(string item) { return string.Equals(item, value, StringComparison.OrdinalIgnoreCase); });
        }

        private static string ResolveRoot(string[] args)
        {
            string explicitRoot = ArgumentValue(args, "--root");
            if (!string.IsNullOrWhiteSpace(explicitRoot)) return Path.GetFullPath(explicitRoot.Trim('"'));
            DirectoryInfo native = new DirectoryInfo(AppDomain.CurrentDomain.BaseDirectory);
            if (native.Parent != null && native.Parent.Parent != null) return native.Parent.Parent.FullName;
            return native.FullName;
        }

        private static string ResolveReportPath(string root, string[] args)
        {
            string explicitReport = ArgumentValue(args, "--report");
            if (!string.IsNullOrWhiteSpace(explicitReport)) return Path.GetFullPath(explicitReport.Trim('"'));

            string version = ValidationLoader.ReadPackageVersion(root);
            var candidates = new List<string>();
            candidates.Add(Path.Combine(root, ".service", "release-validation.json"));
            if (!string.IsNullOrWhiteSpace(version) && !string.Equals(version, "unknown", StringComparison.OrdinalIgnoreCase))
            {
                candidates.Add(Path.Combine(root, "NexRoute-" + version + "-validation.json"));
                DirectoryInfo parent = Directory.GetParent(root);
                if (parent != null) candidates.Add(Path.Combine(parent.FullName, "NexRoute-" + version + "-validation.json"));
            }
            return candidates.FirstOrDefault(delegate(string path) { return File.Exists(path); }) ?? candidates[0];
        }

        private static string ArgumentValue(string[] args, string name)
        {
            for (int index = 0; index < args.Length - 1; index++)
            {
                if (string.Equals(args[index], name, StringComparison.OrdinalIgnoreCase)) return args[index + 1];
            }
            return null;
        }

        private static int WriteSelfTest(ValidationSnapshot snapshot)
        {
            var payload = new Dictionary<string, object>();
            payload["ok"] = snapshot.SchemaValid && snapshot.ReportFound;
            payload["reportFound"] = snapshot.ReportFound;
            payload["schemaValid"] = snapshot.SchemaValid;
            payload["packageVersion"] = snapshot.PackageVersion;
            payload["reportVersion"] = snapshot.ReportVersion;
            payload["overallStatus"] = snapshot.OverallStatus;
            payload["trustState"] = snapshot.TrustState;
            payload["checkCount"] = snapshot.Rows.Count;
            payload["limitationCount"] = snapshot.Rows.Count(delegate(ValidationRow row) { return row.Status == "experimental" || row.Status == "unsupported" || row.Status == "failed"; });
            payload["failedRequiredCount"] = snapshot.Rows.Count(delegate(ValidationRow row) { return row.Required && row.Status == "failed"; });
            payload["error"] = snapshot.Error;
            Console.WriteLine(new JavaScriptSerializer().Serialize(payload));
            return snapshot.SchemaValid && snapshot.ReportFound ? 0 : 2;
        }
    }

    internal sealed class ValidationForm : Form
    {
        private readonly string root;
        private ValidationSnapshot snapshot;
        private readonly Label overallValue;
        private readonly Label trustValue;
        private readonly Label reportValue;
        private readonly Label warningValue;
        private readonly DataGridView grid;
        private readonly Button refreshButton;
        private readonly Button importButton;
        private readonly Button openButton;

        internal ValidationForm(string rootPath, ValidationSnapshot initialSnapshot)
        {
            root = rootPath;
            snapshot = initialSnapshot;
            Text = "NexRoute Validation Viewer";
            MinimumSize = new Size(960, 620);
            Size = new Size(1240, 780);
            StartPosition = FormStartPosition.CenterScreen;
            Font = new Font("Segoe UI", 9F, FontStyle.Regular, GraphicsUnit.Point);
            Icon = SystemIcons.Shield;

            var header = new TableLayoutPanel { Dock = DockStyle.Top, Height = 112, Padding = new Padding(16, 12, 16, 8), ColumnCount = 4, RowCount = 2 };
            header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 30));
            header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 30));
            header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 40));
            header.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 285));
            overallValue = AddCard(header, "RELEASE STATUS", 0);
            trustValue = AddCard(header, "LOCAL TRUST", 1);
            reportValue = AddCard(header, "REPORT", 2);

            var actions = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.LeftToRight, WrapContents = true, Padding = new Padding(8, 4, 0, 0) };
            refreshButton = new Button { Text = "Refresh", AutoSize = true, FlatStyle = FlatStyle.Flat };
            importButton = new Button { Text = "Import JSON", AutoSize = true, FlatStyle = FlatStyle.Flat };
            openButton = new Button { Text = "Open folder", AutoSize = true, FlatStyle = FlatStyle.Flat };
            refreshButton.Click += delegate { Reload(); };
            importButton.Click += delegate { ImportReport(); };
            openButton.Click += delegate { OpenReportFolder(); };
            actions.Controls.Add(refreshButton);
            actions.Controls.Add(importButton);
            actions.Controls.Add(openButton);
            header.Controls.Add(actions, 3, 0);
            header.SetRowSpan(actions, 2);

            warningValue = new Label { Dock = DockStyle.Top, Height = 58, Padding = new Padding(16, 8, 16, 8), AutoEllipsis = true, TextAlign = ContentAlignment.MiddleLeft };

            grid = new DataGridView();
            grid.Dock = DockStyle.Fill;
            grid.ReadOnly = true;
            grid.AllowUserToAddRows = false;
            grid.AllowUserToDeleteRows = false;
            grid.AllowUserToOrderColumns = true;
            grid.AutoGenerateColumns = false;
            grid.AutoSizeRowsMode = DataGridViewAutoSizeRowsMode.AllCells;
            grid.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;
            grid.SelectionMode = DataGridViewSelectionMode.FullRowSelect;
            grid.MultiSelect = false;
            grid.RowHeadersVisible = false;
            AddColumn("Id", "Check", 115);
            AddColumn("Category", "Category", 70);
            AddColumn("Status", "Status", 65);
            AddColumn("RequiredText", "Required", 48);
            AddColumn("Summary", "Summary", 150);
            AddColumn("Evidence", "Evidence", 145);
            AddColumn("Limitation", "Limitation", 165);
            grid.CellFormatting += FormatStatusCell;

            Controls.Add(grid);
            Controls.Add(warningValue);
            Controls.Add(header);
            ApplyTheme();
            Render();
        }

        private Label AddCard(TableLayoutPanel parent, string title, int column)
        {
            var panel = new Panel { Dock = DockStyle.Fill, Margin = new Padding(column == 0 ? 0 : 8, 0, 0, 0), Padding = new Padding(12, 8, 12, 8) };
            var caption = new Label { Text = title, Dock = DockStyle.Top, Height = 18, Font = new Font(Font, FontStyle.Bold) };
            var value = new Label { Text = "—", Dock = DockStyle.Fill, Font = new Font("Segoe UI Semibold", 12F), AutoEllipsis = true, TextAlign = ContentAlignment.MiddleLeft };
            panel.Controls.Add(value);
            panel.Controls.Add(caption);
            parent.Controls.Add(panel, column, 0);
            parent.SetRowSpan(panel, 2);
            return value;
        }

        private void AddColumn(string property, string title, float fillWeight)
        {
            grid.Columns.Add(new DataGridViewTextBoxColumn
            {
                DataPropertyName = property,
                HeaderText = title,
                FillWeight = fillWeight,
                SortMode = DataGridViewColumnSortMode.Automatic,
                DefaultCellStyle = new DataGridViewCellStyle { WrapMode = DataGridViewTriState.True }
            });
        }

        private void Reload()
        {
            snapshot = ValidationLoader.Load(root, snapshot.ReportPath);
            Render();
        }

        private void ImportReport()
        {
            using (var dialog = new OpenFileDialog())
            {
                dialog.Title = "Import NexRoute validation report";
                dialog.Filter = "NexRoute validation JSON|NexRoute-*-validation.json;*.json|JSON files|*.json|All files|*.*";
                dialog.CheckFileExists = true;
                if (dialog.ShowDialog(this) != DialogResult.OK) return;
                ValidationSnapshot candidate = ValidationLoader.Load(root, dialog.FileName);
                if (!candidate.SchemaValid)
                {
                    MessageBox.Show(this, candidate.Error ?? "The selected report is invalid.", "NexRoute Validation", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return;
                }
                string destination = Path.Combine(root, ".service", "release-validation.json");
                Directory.CreateDirectory(Path.GetDirectoryName(destination));
                File.Copy(dialog.FileName, destination, true);
                snapshot = ValidationLoader.Load(root, destination);
                Render();
                MessageBox.Show(this, "The schema-valid report was imported. It remains informational until its GitHub artifact attestation is verified locally.", "NexRoute Validation", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        }

        private void OpenReportFolder()
        {
            string directory = Path.GetDirectoryName(snapshot.ReportPath);
            if (string.IsNullOrWhiteSpace(directory) || !Directory.Exists(directory)) directory = root;
            try { System.Diagnostics.Process.Start("explorer.exe", "\"" + directory + "\""); }
            catch (Exception exception) { MessageBox.Show(this, exception.Message, "NexRoute Validation", MessageBoxButtons.OK, MessageBoxIcon.Error); }
        }

        private void Render()
        {
            overallValue.Text = snapshot.ReportFound ? snapshot.OverallStatus.ToUpperInvariant() : "REPORT MISSING";
            trustValue.Text = snapshot.TrustState.ToUpperInvariant();
            reportValue.Text = snapshot.ReportFound ? Path.GetFileName(snapshot.ReportPath) : "No release report found";
            overallValue.ForeColor = StatusColor(snapshot.OverallStatus);
            trustValue.ForeColor = snapshot.TrustState == "attestation-receipt-matched" ? Color.FromArgb(46, 160, 67) : Color.FromArgb(210, 153, 34);
            warningValue.Text = snapshot.UserNotice;
            warningValue.BackColor = snapshot.SchemaValid && snapshot.TrustState == "attestation-receipt-matched" ? Color.FromArgb(230, 247, 236) : Color.FromArgb(255, 248, 225);
            warningValue.ForeColor = snapshot.SchemaValid && snapshot.TrustState == "attestation-receipt-matched" ? Color.FromArgb(20, 100, 45) : Color.FromArgb(120, 75, 0);
            grid.DataSource = snapshot.Rows.ToList();
        }

        private void FormatStatusCell(object sender, DataGridViewCellFormattingEventArgs e)
        {
            if (e.RowIndex < 0 || e.ColumnIndex < 0) return;
            if (!string.Equals(grid.Columns[e.ColumnIndex].DataPropertyName, "Status", StringComparison.Ordinal)) return;
            string status = Convert.ToString(e.Value, CultureInfo.InvariantCulture) ?? string.Empty;
            e.CellStyle.ForeColor = StatusColor(status);
            e.CellStyle.Font = new Font(grid.Font, FontStyle.Bold);
        }

        private static Color StatusColor(string status)
        {
            if (string.Equals(status, "passed", StringComparison.OrdinalIgnoreCase)) return Color.FromArgb(46, 160, 67);
            if (string.Equals(status, "failed", StringComparison.OrdinalIgnoreCase)) return Color.FromArgb(218, 54, 51);
            if (string.Equals(status, "unsupported", StringComparison.OrdinalIgnoreCase)) return Color.FromArgb(110, 118, 129);
            return Color.FromArgb(210, 153, 34);
        }

        private void ApplyTheme()
        {
            BackColor = Color.FromArgb(246, 248, 250);
            ForeColor = Color.FromArgb(31, 35, 40);
            grid.BackgroundColor = Color.White;
            grid.GridColor = Color.FromArgb(208, 215, 222);
            grid.DefaultCellStyle.BackColor = Color.White;
            grid.DefaultCellStyle.ForeColor = ForeColor;
            grid.DefaultCellStyle.SelectionBackColor = Color.FromArgb(9, 105, 218);
            grid.DefaultCellStyle.SelectionForeColor = Color.White;
            grid.ColumnHeadersDefaultCellStyle.BackColor = Color.FromArgb(234, 238, 242);
            grid.ColumnHeadersDefaultCellStyle.ForeColor = ForeColor;
            grid.EnableHeadersVisualStyles = false;
        }
    }

    internal static class ValidationLoader
    {
        private static readonly string[] AllowedStatuses = { "passed", "experimental", "unsupported", "failed" };

        internal static string ReadPackageVersion(string root)
        {
            string path = Path.Combine(root, ".service", "version.txt");
            try { return File.Exists(path) ? File.ReadAllText(path).Trim() : "unknown"; }
            catch { return "unknown"; }
        }

        internal static ValidationSnapshot Load(string root, string reportPath)
        {
            string packageVersion = ReadPackageVersion(root);
            if (string.IsNullOrWhiteSpace(reportPath) || !File.Exists(reportPath))
            {
                return ValidationSnapshot.Missing(reportPath, packageVersion);
            }

            try
            {
                string raw = File.ReadAllText(reportPath, Encoding.UTF8);
                ValidationDocument document = new JavaScriptSerializer { MaxJsonLength = 4 * 1024 * 1024 }.Deserialize<ValidationDocument>(raw);
                if (document == null) throw new InvalidDataException("The report JSON produced no document.");
                ValidateDocument(document, packageVersion);
                var rows = new List<ValidationRow>();
                foreach (ValidationCheck check in document.checks)
                {
                    rows.Add(new ValidationRow
                    {
                        Id = Clean(check.id),
                        Category = Clean(check.category),
                        Status = Clean(check.status).ToLowerInvariant(),
                        Required = check.required,
                        Summary = Clean(check.summary),
                        Evidence = Clean(check.evidence),
                        Limitation = Clean(check.limitation)
                    });
                }

                string trustState = GetTrustState(reportPath);
                string notice = trustState == "attestation-receipt-matched"
                    ? "The local verification receipt matches this report digest. Experimental and unsupported checks remain explicit limitations."
                    : "This report is schema-valid but its GitHub artifact attestation has not been verified locally. Treat passed rows as informational; experimental and unsupported rows are not successes.";
                return new ValidationSnapshot
                {
                    ReportPath = reportPath,
                    ReportFound = true,
                    SchemaValid = true,
                    PackageVersion = packageVersion,
                    ReportVersion = document.version,
                    OverallStatus = Clean(document.overallStatus).ToLowerInvariant(),
                    TrustState = trustState,
                    Rows = rows,
                    UserNotice = notice
                };
            }
            catch (Exception exception)
            {
                return ValidationSnapshot.Invalid(reportPath, packageVersion, exception.Message);
            }
        }

        private static void ValidateDocument(ValidationDocument document, string packageVersion)
        {
            if (document.schemaVersion != 1) throw new InvalidDataException("Unsupported validation schemaVersion: " + document.schemaVersion.ToString(CultureInfo.InvariantCulture));
            if (!string.Equals(document.product, "NexRoute", StringComparison.Ordinal)) throw new InvalidDataException("The report product is not NexRoute.");
            if (string.IsNullOrWhiteSpace(document.version)) throw new InvalidDataException("The report version is missing.");
            if (!string.Equals(packageVersion, "unknown", StringComparison.OrdinalIgnoreCase) && !string.Equals(document.version, packageVersion, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidDataException("Report version " + document.version + " does not match package version " + packageVersion + ".");
            }
            if (document.checks == null || document.checks.Count == 0) throw new InvalidDataException("The report contains no checks.");
            var ids = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (ValidationCheck check in document.checks)
            {
                if (check == null || string.IsNullOrWhiteSpace(check.id)) throw new InvalidDataException("A validation check has no id.");
                if (!ids.Add(check.id)) throw new InvalidDataException("Duplicate validation check id: " + check.id);
                if (!AllowedStatuses.Contains(Clean(check.status).ToLowerInvariant())) throw new InvalidDataException("Unsupported validation status for " + check.id + ": " + check.status);
            }
            int failedRequired = document.checks.Count(delegate(ValidationCheck check) { return check.required && string.Equals(check.status, "failed", StringComparison.OrdinalIgnoreCase); });
            if (failedRequired > 0 && !string.Equals(document.overallStatus, "failed", StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidDataException("The report contains failed required checks but overallStatus is not failed.");
            }
        }

        private static string GetTrustState(string reportPath)
        {
            string receiptPath = reportPath + ".attestation-receipt.json";
            if (!File.Exists(receiptPath)) return "attestation-not-verified";
            try
            {
                string raw = File.ReadAllText(receiptPath, Encoding.UTF8);
                ValidationReceipt receipt = new JavaScriptSerializer().Deserialize<ValidationReceipt>(raw);
                if (receipt == null || receipt.schemaVersion != 1 || !receipt.verified || string.IsNullOrWhiteSpace(receipt.reportSha256)) return "attestation-receipt-invalid";
                string actual = Sha256(reportPath);
                return string.Equals(actual, receipt.reportSha256.Trim(), StringComparison.OrdinalIgnoreCase)
                    ? "attestation-receipt-matched"
                    : "attestation-receipt-mismatch";
            }
            catch { return "attestation-receipt-invalid"; }
        }

        private static string Sha256(string path)
        {
            using (FileStream stream = File.OpenRead(path))
            using (SHA256 algorithm = SHA256.Create())
            {
                return BitConverter.ToString(algorithm.ComputeHash(stream)).Replace("-", string.Empty).ToLowerInvariant();
            }
        }

        private static string Clean(string value)
        {
            return string.IsNullOrWhiteSpace(value) ? "—" : value.Trim();
        }
    }

    internal sealed class ValidationSnapshot
    {
        internal string ReportPath { get; set; }
        internal bool ReportFound { get; set; }
        internal bool SchemaValid { get; set; }
        internal string PackageVersion { get; set; }
        internal string ReportVersion { get; set; }
        internal string OverallStatus { get; set; }
        internal string TrustState { get; set; }
        internal IList<ValidationRow> Rows { get; set; }
        internal string UserNotice { get; set; }
        internal string Error { get; set; }

        internal static ValidationSnapshot Missing(string path, string packageVersion)
        {
            return new ValidationSnapshot
            {
                ReportPath = path,
                ReportFound = false,
                SchemaValid = false,
                PackageVersion = packageVersion,
                ReportVersion = "unknown",
                OverallStatus = "unverified",
                TrustState = "report-missing",
                Rows = new List<ValidationRow>(),
                UserNotice = "No validation report was found. Interactive tray behavior, adapter events, encrypted DNS and live IPv4/IPv6 bypass remain unverified and must not be presented as passed.",
                Error = "Validation report not found."
            };
        }

        internal static ValidationSnapshot Invalid(string path, string packageVersion, string error)
        {
            return new ValidationSnapshot
            {
                ReportPath = path,
                ReportFound = true,
                SchemaValid = false,
                PackageVersion = packageVersion,
                ReportVersion = "unknown",
                OverallStatus = "failed",
                TrustState = "report-invalid",
                Rows = new List<ValidationRow>(),
                UserNotice = "The validation report is invalid and cannot support any capability claim: " + error,
                Error = error
            };
        }
    }

    internal sealed class ValidationRow
    {
        public string Id { get; set; }
        public string Category { get; set; }
        public string Status { get; set; }
        public bool Required { get; set; }
        public string RequiredText { get { return Required ? "yes" : "no"; } }
        public string Summary { get; set; }
        public string Evidence { get; set; }
        public string Limitation { get; set; }
    }

    internal sealed class ValidationDocument
    {
        public int schemaVersion { get; set; }
        public string product { get; set; }
        public string version { get; set; }
        public string overallStatus { get; set; }
        public List<ValidationCheck> checks { get; set; }
    }

    internal sealed class ValidationCheck
    {
        public string id { get; set; }
        public string category { get; set; }
        public string status { get; set; }
        public bool required { get; set; }
        public string summary { get; set; }
        public string evidence { get; set; }
        public string limitation { get; set; }
    }

    internal sealed class ValidationReceipt
    {
        public int schemaVersion { get; set; }
        public bool verified { get; set; }
        public string reportSha256 { get; set; }
        public string verifiedAtUtc { get; set; }
        public string verifier { get; set; }
    }
}
