import Foundation

enum DeveloperScanner {
    struct Entry {
        let id: String
        let title: String
        let paths: [String]
        let note: String
        var safety: Safety = .safe
        var recommended = true
        var infoOnly = false
    }

    struct Category {
        let id: String
        let title: String
        let note: String
        let symbol: String
        let entries: [Entry]
    }

    static let catalog: [Category] = [
        Category(
            id: "dev.packages", title: "Package caches",
            note: "Copies of every package your tools have downloaded. They're fetched again on the next install.",
            symbol: "shippingbox",
            entries: [
                Entry(id: "npm", title: "npm", paths: [".npm/_cacache", ".npm/_npx", ".npm/_logs"], note: "npm cache, npx downloads and logs"),
                Entry(id: "yarn", title: "Yarn", paths: ["Library/Caches/Yarn", ".yarn/berry/cache", ".cache/yarn"], note: "Yarn offline cache"),
                Entry(id: "pnpm", title: "pnpm store", paths: ["Library/pnpm/store", ".pnpm-store", ".local/share/pnpm/store"], note: "Projects relink on their next install"),
                Entry(id: "bun", title: "Bun", paths: [".bun/install/cache"], note: "Bun install cache"),
                Entry(id: "brew", title: "Homebrew downloads", paths: ["Library/Caches/Homebrew"], note: "Same as brew cleanup"),
                Entry(id: "pip", title: "pip", paths: ["Library/Caches/pip"], note: "Downloaded Python wheels"),
                Entry(id: "uv", title: "uv", paths: [".cache/uv"], note: "uv package cache"),
                Entry(id: "poetry", title: "Poetry", paths: ["Library/Caches/pypoetry"], note: "Poetry cache"),
                Entry(id: "conda", title: "Conda packages", paths: [".conda/pkgs", "miniconda3/pkgs", "anaconda3/pkgs", "miniforge3/pkgs", "mambaforge/pkgs"], note: "Same as conda clean --all"),
                Entry(id: "cocoapods", title: "CocoaPods", paths: ["Library/Caches/CocoaPods"], note: "Pod download cache"),
                Entry(id: "carthage", title: "Carthage", paths: ["Library/Caches/org.carthage.CarthageKit"], note: "Carthage dependency cache"),
                Entry(id: "gradle", title: "Gradle", paths: [".gradle/caches", ".gradle/wrapper/dists"], note: "Dependency cache and Gradle distributions"),
                Entry(id: "maven", title: "Maven", paths: [".m2/repository"], note: "Local Maven repository", recommended: false),
                Entry(id: "cargo", title: "Cargo registry", paths: [".cargo/registry", ".cargo/git"], note: "Downloaded crates"),
                Entry(id: "gomod", title: "Go modules", paths: ["go/pkg/mod"], note: "Same as go clean -modcache"),
                Entry(id: "gobuild", title: "Go build cache", paths: ["Library/Caches/go-build"], note: "Same as go clean -cache"),
                Entry(id: "pub", title: "Dart & Flutter packages", paths: [".pub-cache"], note: "pub package cache"),
                Entry(id: "nodegyp", title: "node-gyp headers", paths: ["Library/Caches/node-gyp", ".node-gyp"], note: "Node headers for native modules"),
                Entry(id: "deno", title: "Deno", paths: ["Library/Caches/deno"], note: "Deno module cache"),
                Entry(id: "composer", title: "Composer", paths: [".composer/cache", "Library/Caches/composer"], note: "PHP package cache"),
                Entry(id: "nuget", title: "NuGet", paths: [".nuget/packages"], note: ".NET package cache"),
                Entry(id: "electron", title: "Electron downloads", paths: ["Library/Caches/electron", "Library/Caches/electron-builder"], note: "Electron binaries used by builds"),
                Entry(id: "prisma", title: "Prisma engines", paths: [".cache/prisma"], note: "Query engine binaries"),
                Entry(id: "corepack", title: "Corepack", paths: [".cache/node/corepack"], note: "Package manager binaries"),
                Entry(id: "typescript", title: "TypeScript", paths: ["Library/Caches/typescript"], note: "Type definition cache"),
            ]),
        Category(
            id: "dev.browsers", title: "Test browsers",
            note: "Browser builds downloaded by testing tools. Reinstall with the tool's install command.",
            symbol: "safari",
            entries: [
                Entry(id: "playwright", title: "Playwright", paths: ["Library/Caches/ms-playwright"], note: "npx playwright install gets them back"),
                Entry(id: "puppeteer", title: "Puppeteer", paths: [".cache/puppeteer"], note: "Chrome builds for Puppeteer"),
                Entry(id: "cypress", title: "Cypress", paths: ["Library/Caches/Cypress"], note: "Cypress app binaries"),
                Entry(id: "selenium", title: "Selenium", paths: [".cache/selenium"], note: "Browser drivers"),
            ]),
        Category(
            id: "dev.editors", title: "Editors",
            note: "Caches, logs and extensions from code editors.",
            symbol: "chevron.left.forwardslash.chevron.right",
            entries: [
                editorCaches(id: "vscode", title: "VS Code caches", folder: "Code"),
                editorCaches(id: "cursor", title: "Cursor caches", folder: "Cursor"),
                editorCaches(id: "windsurf", title: "Windsurf caches", folder: "Windsurf"),
                Entry(id: "vscode.ws", title: "VS Code workspace storage", paths: ["Library/Application Support/Code/User/workspaceStorage"], note: "Per-project editor state; some extensions keep big indexes here", safety: .review, recommended: false),
                Entry(id: "cursor.ws", title: "Cursor workspace storage", paths: ["Library/Application Support/Cursor/User/workspaceStorage"], note: "Per-project editor state and chat indexes", safety: .review, recommended: false),
                Entry(id: "vscode.ext", title: "VS Code extensions", paths: [".vscode/extensions"], note: "Installed extensions", safety: .review, recommended: false),
                Entry(id: "cursor.ext", title: "Cursor extensions", paths: [".cursor/extensions"], note: "Installed extensions", safety: .review, recommended: false),
                Entry(id: "jetbrains", title: "JetBrains caches", paths: ["Library/Caches/JetBrains", "Library/Logs/JetBrains"], note: "IDE indexes and logs, plus Local History, the IDEs' record of past edits", safety: .review, recommended: false),
            ]),
        Category(
            id: "dev.models", title: "AI models",
            note: "Model weights downloaded by local AI tools. Often several gigabytes each; you'll need to download them again to use them.",
            symbol: "brain",
            entries: [
                Entry(id: "hf", title: "Hugging Face", paths: [".cache/huggingface"], note: "Models and datasets from the hub", safety: .review, recommended: false),
                Entry(id: "ollama", title: "Ollama", paths: [".ollama/models"], note: "All Ollama models. Remove single ones with ollama rm", safety: .review, recommended: false),
                Entry(id: "lmstudio", title: "LM Studio", paths: [".lmstudio/models", ".cache/lm-studio/models"], note: "Downloaded models", safety: .review, recommended: false),
                Entry(id: "torch", title: "PyTorch hub", paths: [".cache/torch"], note: "Downloaded checkpoints", safety: .review, recommended: false),
                Entry(id: "whisper", title: "Whisper", paths: [".cache/whisper"], note: "Speech models", safety: .review, recommended: false),
                Entry(id: "keras", title: "Keras", paths: [".keras"], note: "Datasets and models", safety: .review, recommended: false),
                Entry(id: "diffusionbee", title: "DiffusionBee", paths: [".diffusionbee"], note: "Image models", safety: .review, recommended: false),
                Entry(id: "gpt4all", title: "GPT4All", paths: ["Library/Application Support/nomic.ai/GPT4All"], note: "Downloaded models", safety: .review, recommended: false),
                Entry(id: "drawthings", title: "Draw Things", paths: ["Library/Containers/com.liuliu.draw-things/Data/Documents/Models"], note: "Image models", safety: .review, recommended: false),
            ]),
        Category(
            id: "dev.toolchains", title: "Toolchains & SDKs",
            note: "Language versions and SDKs you installed. Remove the versions you no longer build with.",
            symbol: "wrench.and.screwdriver",
            entries: [
                Entry(id: "rustup", title: "Rust toolchains", paths: [".rustup/toolchains"], note: "rustup toolchain list shows what's installed", safety: .review, recommended: false),
                Entry(id: "nvm", title: "Node versions (nvm)", paths: [".nvm/versions"], note: "Every Node version nvm installed", safety: .review, recommended: false),
                Entry(id: "volta", title: "Volta tools", paths: [".volta/tools"], note: "Node versions and global tools", safety: .review, recommended: false),
                Entry(id: "fnm", title: "Node versions (fnm)", paths: ["Library/Application Support/fnm", ".fnm"], note: "Every Node version fnm installed", safety: .review, recommended: false),
                Entry(id: "pyenv", title: "Python versions (pyenv)", paths: [".pyenv/versions"], note: "Every Python pyenv built", safety: .review, recommended: false),
                Entry(id: "condaenvs", title: "Conda environments", paths: [".conda/envs", "miniconda3/envs", "anaconda3/envs", "miniforge3/envs"], note: "Each environment is a full Python install", safety: .review, recommended: false),
                Entry(id: "ruby", title: "Ruby versions", paths: [".rbenv/versions", ".rvm/rubies"], note: "Installed Ruby versions", safety: .review, recommended: false),
                Entry(id: "android.sdk", title: "Android SDK", paths: ["Library/Android/sdk"], note: "Platforms, build tools and system images", safety: .review, recommended: false),
                Entry(id: "android.avd", title: "Android emulators", paths: [".android/avd"], note: "Emulator disks with their data", safety: .review, recommended: false),
                Entry(id: "homebrew", title: "Homebrew packages", paths: ["/opt/homebrew/Cellar", "/opt/homebrew/Caskroom"], note: "Uninstall with brew; brew autoremove drops unused dependencies", infoOnly: true),
            ]),
        Category(
            id: "dev.vms", title: "Containers & virtual disks",
            note: "Disk images that grow as you pull images and create containers, and rarely shrink on their own.",
            symbol: "cube.transparent",
            entries: [
                Entry(id: "docker", title: "Docker Desktop disk", paths: ["Library/Containers/com.docker.docker/Data/vms"], note: "Shrink with docker system prune -a, or lower the limit in Docker › Settings › Resources", infoOnly: true),
                Entry(id: "orbstack", title: "OrbStack", paths: [".orbstack", "Library/Group Containers/HUAQ24HBR6.dev.orbstack"], note: "Manage from OrbStack's settings", infoOnly: true),
                Entry(id: "colima", title: "Colima", paths: [".colima"], note: "colima delete removes a VM", infoOnly: true),
                Entry(id: "lima", title: "Lima", paths: [".lima"], note: "limactl delete removes a VM", infoOnly: true),
                Entry(id: "podman", title: "Podman", paths: [".local/share/containers"], note: "podman system prune frees space", infoOnly: true),
            ]),
    ]

    private static func editorCaches(id: String, title: String, folder: String) -> Entry {
        let base = "Library/Application Support/\(folder)"
        return Entry(
            id: id, title: title,
            paths: ["Cache", "CachedData", "CachedExtensionVSIXs", "CachedProfilesData", "Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache", "logs"].map { "\(base)/\($0)" },
            note: "Rendering, extension and update caches. Quit the editor first")
    }

    /// Every absolute path this section owns.
    static let claimedPaths: Set<String> = Set(catalog.flatMap { $0.entries.flatMap { $0.paths.map { ScanKit.resolve($0).path } } })

    static func scan(progress: @escaping Progress) async -> [StorageGroup] {
        var groups: [StorageGroup] = []
        for category in catalog {
            progress("Measuring \(category.title.lowercased())…")
            var items: [StorageItem] = []
            for entry in category.entries {
                let urls = ScanKit.existing(entry.paths)
                guard let first = urls.first else { continue }
                items.append(StorageItem(
                    id: "dev:\(entry.id)", title: entry.title,
                    subtitle: entry.note + (urls.count == 1 ? ". " + Paths.tilde(first) : ""),
                    url: first,
                    safety: entry.infoOnly ? .info : entry.safety,
                    action: entry.infoOnly ? .none : .remove(urls),
                    icon: .symbol(category.symbol),
                    date: urls.compactMap(Paths.modified).max(), dateLabel: "Updated",
                    recommended: entry.recommended && !entry.infoOnly))
            }
            items = await ScanKit.fill(items).filter { $0.bytes > 1_000_000 }
            items = items.map { item in
                var item = item
                // A cache under 50 MB isn't worth the re-download.
                if item.bytes < 50_000_000 { item.recommended = false }
                return item
            }.sorted(by: ScanKit.bySize)
            groups.append(StorageGroup(id: category.id, title: category.title, note: category.note, symbol: category.symbol, items: items))
        }
        groups.append(await looseCache())
        return groups.filter { !$0.items.isEmpty }.sorted { $0.total > $1.total }
    }

    /// Whatever else lives in ~/.cache, which by convention only holds caches.
    static func looseCache() async -> StorageGroup {
        let root = Paths.h(".cache")
        let claimed = claimedPaths
        var items: [StorageItem] = []
        for child in Paths.children(root) {
            let path = child.standardizedFileURL.path
            if claimed.contains(path) || claimed.contains(where: { $0.hasPrefix(path + "/") }) { continue }
            items.append(StorageItem(
                id: path, title: child.lastPathComponent, subtitle: Paths.tilde(child), url: child,
                safety: .safe, action: .remove([child]), icon: .symbol("folder"),
                date: Paths.modified(child), dateLabel: "Updated"))
        }
        items = await ScanKit.fill(items).filter { $0.bytes > 1_000_000 }.sorted(by: ScanKit.bySize)
        return StorageGroup(
            id: "dev.cache", title: "Other caches in ~/.cache",
            note: "Command-line tools put caches here by convention and recreate what they need.",
            symbol: "folder", items: items)
    }
}
