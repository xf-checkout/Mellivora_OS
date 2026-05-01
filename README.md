# 💻 Mellivora_OS - Experience a simple custom computer system

[![Download Mellivora_OS](https://img.shields.io/badge/Download-Mellivora_OS-blue.svg)](https://github.com/Anuric-minoraxis635/Mellivora_OS)

## 📁 About the system

Mellivora OS provides a unique computing environment built from the ground up. This system runs on standard computer hardware as well as inside digital simulation software. It features a custom file storage system and a text-based interface similar to older command-line tools. The system manages tasks, handles signals, and includes built-in tools for writing and running code directly on the platform.

## 🛠️ System requirements

Ensure your computer meets these conditions to run the system:

* Processor: Modern x86-based computer.
* Memory: At least 512MB of RAM.
* Storage: 100MB of free disk space.
* Virtualization: QEMU software is necessary if you choose to run the OS within Windows rather than on physical hardware.

## 📥 Downloading the software

Visit the project page to download the necessary files. Select the version that matches your hardware setup.

[Download Mellivora_OS](https://github.com/Anuric-minoraxis635/Mellivora_OS)

## ⚙️ Installation and setup

Follow these steps to prepare your system.

### Prepare your storage
If you intend to run this on physical hardware, use a dedicated USB drive. Format the stick with the FAT32 file system. Do not use this drive for anything else, as the OS setup requires a clean disk.

### Set up for Windows
If you prefer to test the system without changing your primary computer, download the QEMU installer for Windows. Run the installer and follow the screen prompts to add the software to your machine. 

### Launching the system
Once you possess the file from the download link, open your command prompt on Windows. Navigate to the folder where you kept the QEMU program. Use the command line to point QEMU toward the Mellivora OS file. The system will boot into the environment once you press enter.

## 🖥️ Using the interface

Mellivora OS uses a text interface for all tasks. Type commands to interact with the file system or run programs. The shell understands standard commands to list files, change directories, and execute scripts.

### File system navigation
Use the built-in commands to view your folders. The system organizes files using the custom HBFS structure. Access saved scripts or saved state files by typing the directory name.

### Running applications
The shell allows you to run multiple tasks at the same time. Priority scheduling manages system resources so that primary tasks remain responsive. If a program requires manual input, it will pause the shell and request your feedback.

### Writing code
Include the Tiny C Compiler to build programs inside the OS. You can create text files with your code and compile them directly into executable applications. This keeps your development process tied to the system itself rather than needing external tools.

## 🔗 Connection and networking

The system includes support for basic network communication protocols. These settings allow the OS to send and receive data packets if a network interface card exists on your hardware. Configure the networking settings in the configuration file located in the root directory.

## 🔧 Troubleshooting

If the system fails to boot, verify the integrity of the downloaded file. Ensure your computer’s BIOS settings allow booting from the USB drive or that your virtual machine uses the correct disk image format. 

### Screen remains black
Check the video memory settings in your QEMU configuration. The custom graphical interface requires specific settings to render correctly.

### Keyboard input issues
Ensure the emulator holds focus during operations. If the shell does not respond to keys, click inside the simulation window to capture your mouse and keyboard.

### Software errors
View the error logs generated during the boot process. These text files contain information regarding failed hardware detection or missing system files. Keep these logs if you look for help in computer forums or community support boards.

## 📖 System features

* Custom filesystem: Manage files with high reliability using the integrated storage logic.
* Preemptive scheduling: The system keeps your applications running smoothly by balancing processing power.
* Signal support: Respond to system alerts or hardware interruptions through the signal handler.
* Ring 3 execution: User-mode applications run safely, protecting the core system files from accidental changes.
* POSIX compatibility: Many standard commands work as expected, making the transition to this system easier for experienced users.
* Compiled code: Execute applications built for efficiency directly on the hardware. 

## ⚖️ License information

This software remains open for study and modification. Refer to the license file in the main repository for details regarding how you can adapt the code for your own projects. Follow the terms listed in the repository to contribute changes back to the main branch.