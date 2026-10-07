allprojects {
    repositories {
        // 本地 maven（ffmpeg-kit-min 2.2.3 aar 在 aliyun/central 偶发拉取失败，
        // 已手动放置 ~/.m2 —— mavenLocal 优先兜底）
        mavenLocal()
        // 国内镜像优先（google/central 直连超时）
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/central")
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
