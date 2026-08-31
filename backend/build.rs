use std::env;
use std::fs;
use std::path::PathBuf;

fn main() {
    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    let migrations_dir = manifest_dir.join("migrations");
    let mut entries: Vec<_> = Vec::new();
    if migrations_dir.exists() {
        entries = fs::read_dir(&migrations_dir)
            .unwrap()
            .filter_map(|e| e.ok())
            .map(|e| e.path())
            .filter(|p| p.extension().map_or(false, |x| x == "sql"))
            .collect();
        entries.sort();
    }
    let mut out = String::new();
    out.push_str("pub static MIGRATIONS: &[&str] = &[\n");
    for p in &entries {
        let sql = fs::read_to_string(p).unwrap();
        // 用 {:?} 把 SQL 转成 Rust 字符串字面量，自动处理所有转义
        out.push_str(&format!("    {},\n", format!("{:?}", sql)));
    }
    out.push_str("];\n");
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
    fs::write(out_dir.join("migrations.rs"), out).unwrap();
    println!("cargo:rerun-if-changed=migrations/");
}
