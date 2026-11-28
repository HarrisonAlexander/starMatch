using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;

// Launcher installed by the MSI. Unlike Launcher.cs it embeds nothing: the
// scripts sit next to it in the install folder, so it just starts
// powershell.exe against TrueHire.ps1 without a console window.
public static class AppLauncher
{
    [STAThread]
    public static int Main()
    {
        try
        {
            string dir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
            ProcessStartInfo psi = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = string.Format(
                    "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"{0}\"",
                    Path.Combine(dir, "TrueHire.ps1")),
                WorkingDirectory = dir,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            Process.Start(psi);
            return 0;
        }
        catch (Exception ex)
        {
            try
            {
                File.AppendAllText(Path.Combine(Path.GetTempPath(), "TrueHire-launcher-error.txt"),
                    DateTime.Now.ToString("o") + " " + ex + Environment.NewLine);
            }
            catch { }
            return 1;
        }
    }
}
