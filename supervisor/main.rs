use std::{env,fs::{self,OpenOptions},io,process::{Command,Stdio},thread,time::{Duration,SystemTime,UNIX_EPOCH}};

fn main() -> io::Result<()> {
    let root=env::current_exe()?.parent().and_then(|p|p.parent()).and_then(|p|p.parent()).unwrap().to_path_buf();
    let trainer=root.join("build-native").join("bin").join("Release").join("rocket_learn_native.exe");
    let custom_runtime=env::var_os("RL_RUNTIME_ROOT").map(std::path::PathBuf::from)
        .unwrap_or_else(|| std::path::PathBuf::from(r"D:\GigaLearnCPP_GLAZE_DISCRETE"));
    let zluda=custom_runtime.join("deps").join("zluda").join("zluda.exe");
    let logs=root.join("logs");fs::create_dir_all(&logs)?;
    let stamp=SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs();
    let log_path=logs.join(format!("training-{stamp}.log"));
    println!("supervisor log={}",log_path.display());
    loop {
        let out=OpenOptions::new().create(true).append(true).open(&log_path)?;
        let err=out.try_clone()?;
        let mut cmd=if zluda.exists(){let mut c=Command::new(&zluda);c.arg("--").arg(&trainer);c}else{Command::new(&trainer)};
        let runtime=custom_runtime.join("build-cu118").join("Release");
        let rocm=r"C:\Program Files\AMD\ROCm\6.4\bin";
        let zluda_dir=custom_runtime.join("deps").join("zluda");
        let path=format!("{};{};{};{}",rocm,zluda_dir.display(),runtime.display(),env::var("PATH").unwrap_or_default());
        let status=cmd.current_dir(&root).env("PATH",path).env("ROCBLAS_TENSILE_LIBPATH",r"C:\Program Files\AMD\ROCm\6.4\bin\rocblas\library")
            .env("HIPBLASLT_TENSILE_LIBPATH",r"C:\Program Files\AMD\ROCm\6.4\bin\hipblaslt\library").env("ZLUDA_CC","8.6")
            .stdout(Stdio::from(out)).stderr(Stdio::from(err)).status()?;
        eprintln!("trainer exited {status}; restarting in 10 seconds");thread::sleep(Duration::from_secs(10));
    }
}
