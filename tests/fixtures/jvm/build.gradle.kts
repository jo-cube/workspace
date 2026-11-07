plugins {
    kotlin("jvm") version "2.4.21"
    application
}

repositories {
    mavenCentral()
}

application {
    mainClass.set("smoke.MainKt")
}
