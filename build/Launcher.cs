using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;

public static class Launcher
{
    [STAThread]
    public static int Main()
    {
        const string appFolder   = @"TrueHire";
        const string entryScript = @"TrueHire.ps1";
        const string hash        = "__BUNDLE_HASH__";   // stamped by Build-Exe.ps1

        try
        {
            string root = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                appFolder);
            string target = Path.Combine(root, hash);
            string marker = Path.Combine(target, ".unpacked");

            if (!File.Exists(marker))
            {
                if (Directory.Exists(target))
                {
                    try { Directory.Delete(target, true); } catch { }
                }
                Directory.CreateDirectory(target);

                Assembly asm = Assembly.GetExecutingAssembly();
                using (Stream rs = asm.GetManifestResourceStream("bundle.zip"))
                {
                    if (rs == null) throw new Exception("Embedded bundle.zip resource missing.");
                    using (ZipArchive archive = new ZipArchive(rs, ZipArchiveMode.Read))
                    {
                        foreach (ZipArchiveEntry entry in archive.Entries)
                        {
                            string dest = Path.Combine(target, entry.FullName);
                            if (string.IsNullOrEmpty(entry.Name))
                            {
                                Directory.CreateDirectory(dest);
                            }
                            else
                            {
                                Directory.CreateDirectory(Path.GetDirectoryName(dest));
                                entry.ExtractToFile(dest, true);
                            }
                        }
                    }
                }

                File.WriteAllText(marker, DateTime.UtcNow.ToString("o"));

                // Purge older extractions under the same AppFolder root.
                foreach (string d in Directory.GetDirectories(root))
                {
                    if (!string.Equals(Path.GetFileName(d), hash, StringComparison.OrdinalIgnoreCase))
                    {
                        try { Directory.Delete(d, true); } catch { }
                    }
                }
            }

            string script = Path.Combine(target, entryScript);
            string exeDir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
            ProcessStartInfo psi = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = string.Format(
                    "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"{0}\"",
                    script),
                WorkingDirectory = target,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            // Tell the spawned PowerShell where the EXE itself lives, so apps
            // that opt into "data lives next to the EXE" can write user state
            // there instead of in the extracted temp folder (which gets purged
            // on every EXE update). The env var is named "<APPFOLDER>_DATA_ROOT"
            // and points to "<exeDir>\\userdata\\". Harmless for apps that
            // don't read it.
            psi.EnvironmentVariables[appFolder.ToUpperInvariant() + "_DATA_ROOT"] =
                Path.Combine(exeDir, "userdata");
            Process.Start(psi);
            return 0;
        }
        catch (Exception ex)
        {
            try
            {
                string err = Path.Combine(Path.GetTempPath(),
                    appFolder + "-launcher-error.txt");
                File.AppendAllText(err,
                    DateTime.Now.ToString("o") + " " + ex + Environment.NewLine);
            }
            catch { }
            return 1;
        }
    }
}
