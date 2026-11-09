// Foglio fork: upstream derives the release string (used by INFO("release")) from
// `git describe` in the *current* directory, which for a vendored copy would be the
// Foglio repository. Use a fixed string instead so builds are reproducible.
fn main() {
    println!("cargo:rustc-env=GIT_VERSION=0.9.1-foglio");
}
