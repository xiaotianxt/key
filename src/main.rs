use std::process::ExitCode;

fn main() -> ExitCode {
    match key::run() {
        Ok(code) => code,
        Err(error) => {
            eprintln!("key: {error:#}");
            ExitCode::FAILURE
        }
    }
}
