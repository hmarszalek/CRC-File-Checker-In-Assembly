# CRC File Checker

## Overview

This project implements a CRC (Cyclic Redundancy Code) checksum calculator for files with gaps in Linux, using assembly language. The program reads fragmented data from a specified file and calculates the CRC based on the provided polynomial.

## Features

-   Reads files with fragmented data.
-   Calculates CRC using a user-defined polynomial.
-   Outputs the CRC as a binary string followed by a newline.
-   Utilizes Linux system calls for file operations.

## Usage

To use this program, you will need an x86-64 assembler such as NASM. Follow these steps to compile and run the program:

1. **Install NASM:** if you haven't already. You can install them using your package manager. For example, on Ubuntu:

    ```bash
    sudo apt-get install nasm
    ```

2. **Compile and link the Assembly Code:**

    ```bash
    nasm -f elf64 crc.asm -o crc.o
    ld crc.o -o crc
    ```

3. **Run the Program:**

    ```bash
    ./crc <file> <crc_poly>
    ```

Replace `<file>` with the desired input file and `<crc_poly>` with the CRC polynomial (e.g., `11010101`).

## Code Structure

The assembly code is organized into several key sections that work together to calculate the CRC checksum for files with fragmented data. Below is an overview of the main components:

-   **Data Section**: This section defines variables and buffers needed for file handling, input storage, and CRC calculation. It includes:

    -   `fd`: File descriptor for the opened file.
    -   `file`: Buffer for the file path (256 bytes).
    -   `poly`: Buffer for the CRC polynomial string (64 bytes).
    -   `crc`: Integer representation of the CRC polynomial.
    -   `control_sum`: Buffer for the calculated checksum (65 bytes including a newline).
    -   `data`: Buffer for reading data blocks (2048 bytes).
    -   `data_len`: Variable to track the length of the data read.

-   **Text Section**: The main logic of the program resides here, starting with the `_start` label, which serves as the entry point. Key functionalities include:
    -   **Parameter Validation**: Checks the number of command-line arguments and validates the CRC polynomial.
    -   **File Handling**: Opens the specified file, reads its content in blocks, and handles any errors during file operations.
    -   **CRC Calculation**: Implements the division algorithm to compute the CRC checksum by processing data byte by byte and using bitwise operations.
    -   **Helper Functions**: Contains several utility functions for:
        -   Reading from the file.
        -   Filling the data buffer.
        -   Converting the CRC result to a binary string for output.
        -   Calculating the length of strings and handling padding bits.

Each of these sections is crucial for ensuring the program runs correctly and efficiently while accurately calculating the CRC checksum based on the specified polynomial.

## Contributions

Contributions are welcome! Please feel free to open issues or submit pull requests for improvements or bug fixes.

## Author

Hanna Marszałek
