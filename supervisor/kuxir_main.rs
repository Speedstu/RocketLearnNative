use std::{
    env,
    fs::{self, OpenOptions},
    io::{self, BufRead, BufReader, Write},
    process::{Command, Stdio},
    thread,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

fn main() -> io::Result<()> {
    let root = env::current_exe()?.parent().and_then(|p| p.parent()).and_then(|p| p.parent()).unwrap().to_path_buf();
    let trainer = root.join("build-native").join("bin").join("Release").join("rocket_kuxir_native.exe");
    let runtime_root = env::var_os("RL_RUNTIME_ROOT").map(std::path::PathBuf::from)
        .unwrap_or_else(|| std::path::PathBuf::from(r"D:\GigaLearnCPP_GLAZE_DISCRETE"));
    let zluda = runtime_root.join("deps").join("zluda").join("zluda.exe");
    let logs = root.join("logs");
    fs::create_dir_all(&logs)?;
    let stamp = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs();
    let log_path = logs.join(format!("kuxir-training-{stamp}.log"));
    println!("kuxir supervisor log={}", log_path.display());
    loop {
        let mut output_log = OpenOptions::new().create(true).append(true).open(&log_path)?;
        let mut error_log = output_log.try_clone()?;
        let mut command = if zluda.exists() {
            let mut cmd = Command::new(&zluda);
            cmd.arg("--").arg(&trainer);
            cmd
        } else {
            Command::new(&trainer)
        };
        let cuda_runtime = runtime_root.join("build-cu118").join("Release");
        let rocm = r"C:\Program Files\AMD\ROCm\6.4\bin";
        let zluda_dir = runtime_root.join("deps").join("zluda");
        let path = format!("{};{};{};{}", rocm, zluda_dir.display(), cuda_runtime.display(), env::var("PATH").unwrap_or_default());
        let mut child = command.current_dir(&root)
            .env("PATH", path)
            .env("ROCBLAS_TENSILE_LIBPATH", r"C:\Program Files\AMD\ROCm\6.4\bin\rocblas\library")
            .env("HIPBLASLT_TENSILE_LIBPATH", r"C:\Program Files\AMD\ROCm\6.4\bin\hipblaslt\library")
            .env("ZLUDA_CC", "8.6")
            .stdout(Stdio::piped()).stderr(Stdio::piped()).spawn()?;

        let stdout = child.stdout.take().expect("trainer stdout pipe missing");
        let stderr = child.stderr.take().expect("trainer stderr pipe missing");
        let error_thread = thread::spawn(move || -> io::Result<()> {
            for line in BufReader::new(stderr).lines() {
                let line = line?;
                eprintln!("{line}");
                writeln!(error_log, "{line}")?;
                error_log.flush()?;
            }
            Ok(())
        });

        for line in BufReader::new(stdout).lines() {
            let line = line?;
            println!("{line}");
            writeln!(output_log, "{line}")?;
            output_log.flush()?;
        }
        let status = child.wait()?;
        if let Ok(result) = error_thread.join() { result?; }
        eprintln!("kuxir trainer exited {status}; restarting in 10 seconds");
        thread::sleep(Duration::from_secs(10));
    }
}
