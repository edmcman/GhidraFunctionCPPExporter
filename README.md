# Function C/C++ Exporter for Ghidra

## Overview

The Function C/C++ Exporter is an enhanced alternative to Ghidra's built-in CppExporter. It was created with the primary goal of exporting decompiled code that can be successfully compiled one function at a time, addressing limitations in the default exporter. Specifically, it is able to export only a subset of functions, and will only include the necessary type definitions,  function declarations, and global definitions for these functions.

## Features

- **Function-Level Compilation**: Precisely target individual functions or address ranges for export and compilation
- **Decompiler Parameter ID**: Optionally enables the Decompiler Parameter ID analyzer for improved function parameter detection
- **Export Formats**: Generate C source files and/or header files
- **Flexible Filtering**: Filter functions by tags, address ranges, or function names
- **Function Declarations**: Include function prototypes for referenced functions
- **Optimized Type Export**: Export only necessary data types and globals

## Usage

### Simple Frontend (Recommended)

For easier usage, a bash frontend script is provided that automatically handles temporary project creation and cleanup:

```bash
# Basic export - exports all functions
./export.bash ./examples/ls

# Export a specific function
./export.bash ./examples/ls address_set_str "0x1124c0"

# Export with custom options
./export.bash binary.exe create_header_file true output_dir exported_code
```

The script requires the `GHIDRA_INSTALL_DIR` environment variable to be set:
```bash
export GHIDRA_INSTALL_DIR=/path/to/your/ghidra/installation
```

### Direct Ghidra Usage

You can also call the exporter directly using Ghidra's analyzeHeadless command:

### Compiling a Single Function

One of the key advantages of this exporter is the ability to work with individual functions. To export and compile a single function:

```bash
# Export just the 0x1124c0 function
$GHIDRA_INSTALL_DIR/analyzeHeadless ~/ghidra_projects MyProject -import ./examples/ls \
  -preScript ./cpp_exporter_headless.py \
  address_set_str "0x1124c0"
```

This results in the below `ls.c` file.  This particular function was chosen because it is very complex, and does not compile because of limitations of Ghidra's decompiler. However,  note that all referenced types and functions are included.

<details>
<summary>ls.c</summary>

``` c

//==============================================================================
// DATA TYPES                                                                
// These types were decompiled from the binary and may not match original source
//==============================================================================

typedef unsigned char   undefined;

typedef unsigned char    bool;
typedef unsigned char    byte;
typedef unsigned char    dwfenc;
typedef unsigned int    dword;
typedef unsigned long    qword;
typedef unsigned char    uchar;
typedef unsigned int    uint;
typedef unsigned long    ulong;
typedef unsigned char    undefined1;
typedef unsigned short    undefined2;
typedef unsigned int    undefined3;
typedef unsigned int    undefined4;
typedef unsigned long    undefined8;
typedef unsigned short    ushort;
typedef int    wchar_t;
typedef unsigned short    word;
#define unkbyte9   unsigned long long
#define unkbyte10   unsigned long long
#define unkbyte11   unsigned long long
#define unkbyte12   unsigned long long
#define unkbyte13   unsigned long long
#define unkbyte14   unsigned long long
#define unkbyte15   unsigned long long
#define unkbyte16   unsigned long long

#define unkuint9   unsigned long long
#define unkuint10   unsigned long long
#define unkuint11   unsigned long long
#define unkuint12   unsigned long long
#define unkuint13   unsigned long long
#define unkuint14   unsigned long long
#define unkuint15   unsigned long long
#define unkuint16   unsigned long long

#define unkint9   long long
#define unkint10   long long
#define unkint11   long long
#define unkint12   long long
#define unkint13   long long
#define unkint14   long long
#define unkint15   long long
#define unkint16   long long

#define unkfloat1   float
#define unkfloat2   float
#define unkfloat3   float
#define unkfloat5   double
#define unkfloat6   double
#define unkfloat7   double
#define unkfloat9   long double
#define unkfloat11   long double
#define unkfloat12   long double
#define unkfloat13   long double
#define unkfloat14   long double
#define unkfloat15   long double
#define unkfloat16   long double

#define BADSPACEBASE   void
#define code   void

// C99 lacks bool, define it as byte for C-only output
#ifndef __cplusplus
typedef unsigned char bool;
#endif

typedef long __blkcnt_t;

typedef ulong size_t;

typedef uint __uid_t;

typedef long __time_t;

typedef struct stat stat, *Pstat;

typedef ulong __dev_t;

typedef ulong __ino_t;

typedef ulong __nlink_t;

typedef uint __mode_t;

typedef uint __gid_t;

typedef long __off_t;

typedef long __blksize_t;

typedef struct timespec timespec, *Ptimespec;

struct timespec {
    __time_t tv_sec;
    long tv_nsec;
};

struct stat {
    __dev_t st_dev;
    __ino_t st_ino;
    __nlink_t st_nlink;
    __mode_t st_mode;
    __uid_t st_uid;
    __gid_t st_gid;
    int __pad0;
    __dev_t st_rdev;
    __off_t st_size;
    __blksize_t st_blksize;
    __blkcnt_t st_blocks;
    struct timespec st_atim;
    struct timespec st_mtim;
    struct timespec st_ctim;
    long __unused[3];
};




//==============================================================================
// FUNCTION DECLARATIONS                                                     
// These function prototypes were extracted from binary analysis             
//==============================================================================

char * FUN_0010c3e0(char *param_1,ulong param_2);
char * FUN_001124c0(char *param_1);
char * getcwd(char * __buf, size_t __size);
int * __errno_location(void);
int lstat(char * __file, stat * __buf);
size_t strlen(char * __s);
ulong FUN_00106f60(undefined8 *param_1,ulong param_2);
undefined __stack_chk_fail();
undefined8 *FUN_001123f0(ulong param_1,undefined8 param_2,undefined8 param_3,undefined8 param_4,undefined8 param_5);
undefined8 FUN_00108950(undefined8 *param_1,undefined8 *param_2);
undefined8 FUN_0010caa0(long *param_1,long param_2,long *param_3);
void * malloc(size_t __size);
void * memcpy(void * __dest, void * __src, size_t __n);
void * memmove(void * __dest, void * __src, size_t __n);
void * realloc(void * __ptr, size_t __size);
void FUN_00104d04(void);
void FUN_00106fc0(undefined8 *param_1);
void FUN_0010c9b0(ulong *param_1);
void FUN_0010dd70(void);
void FUN_0010e640(char *param_1);
void free(void * __ptr);


//==============================================================================
// FUNCTION IMPLEMENTATIONS                                                  
// Decompiled code from the binary                                           
//==============================================================================

char * FUN_001124c0(char *param_1)

{
  bool bVar1;
  long lVar2;
  char cVar3;
  char cVar4;
  int iVar5;
  char *pcVar6;
  size_t sVar7;
  char *__file;
  ulong uVar8;
  undefined8 uVar9;
  size_t sVar10;
  char *pcVar11;
  char *pcVar12;
  int *piVar13;
  long *plVar14;
  char *pcVar15;
  char **ppcVar16;
  char *pcVar17;
  char *pcVar18;
  long in_FS_OFFSET;
  ulong *local_130;
  char *local_118;
  char *local_110;
  ulong local_108;
  char *local_f8;
  __ino_t local_f0;
  __dev_t local_e8;
  stat local_d8;
  long local_40;
  
  local_40 = *(long *)(in_FS_OFFSET + 0x28);
  if (param_1 == (char *)0x0) {
    piVar13 = __errno_location();
    pcVar6 = (char *)0x0;
    *piVar13 = 0x16;
    goto LAB_00112978;
  }
  if (*param_1 == '\0') {
    piVar13 = __errno_location();
    pcVar6 = (char *)0x0;
    *piVar13 = 2;
    goto LAB_00112978;
  }
  if (*param_1 == '/') {
    pcVar12 = (char *)malloc(0x1000);
    if (pcVar12 == (char *)0x0) goto LAB_0011294a;
    *pcVar12 = '/';
    pcVar15 = pcVar12 + 0x1000;
    pcVar18 = pcVar12 + 1;
    cVar4 = '/';
LAB_00112547:
    local_130 = (ulong *)0x0;
    local_110 = (char *)0x0;
    local_108 = 0;
    local_118 = param_1;
    do {
      pcVar6 = param_1;
      cVar3 = cVar4;
      if (cVar4 == '/') {
        do {
          cVar3 = param_1[1];
          param_1 = param_1 + 1;
        } while (cVar3 == '/');
        pcVar6 = param_1;
        if (cVar3 == '\0') break;
      }
      do {
        pcVar11 = param_1;
        cVar4 = pcVar11[1];
        param_1 = pcVar11 + 1;
        if (cVar4 == '\0') break;
      } while (cVar4 != '/');
      if (param_1 == pcVar6) break;
      sVar7 = (long)param_1 - (long)pcVar6;
      if (sVar7 == 1) {
        if (cVar3 != '.') goto LAB_001125dc;
      }
      else if (((sVar7 == 2) && (cVar3 == '.')) && (pcVar6[1] == '.')) {
        if ((pcVar12 + 1 < pcVar18) && (pcVar18 = pcVar18 + -1, pcVar12 < pcVar18)) {
          do {
            if (pcVar18[-1] == '/') break;
            pcVar18 = pcVar18 + -1;
          } while (pcVar18 != pcVar12);
        }
      }
      else {
LAB_001125dc:
        pcVar17 = pcVar18;
        if (pcVar18[-1] != '/') {
          *pcVar18 = '/';
          pcVar17 = pcVar18 + 1;
        }
        __file = pcVar12;
        if (pcVar15 <= pcVar17 + sVar7) {
          lVar2 = 0x1000 - (long)pcVar12;
          if (0xfff < (long)sVar7) {
            lVar2 = (sVar7 + 1) - (long)pcVar12;
          }
          pcVar15 = pcVar15 + lVar2;
          if ((pcVar15 == (char *)0x0) && (pcVar12 != (char *)0x0)) {
            __file = (char *)0x0;
            free(pcVar12);
          }
          else {
            __file = (char *)realloc(pcVar12,(size_t)pcVar15);
            if ((__file == (char *)0x0) && (pcVar15 != (char *)0x0)) goto LAB_0011294a;
          }
          pcVar15 = __file + (long)pcVar15;
          pcVar17 = __file + ((long)pcVar17 - (long)pcVar12);
        }
        pcVar18 = pcVar17 + sVar7;
        memcpy(pcVar17,pcVar6,sVar7);
        *pcVar18 = '\0';
        iVar5 = lstat(__file,&local_d8);
        pcVar6 = pcVar18;
        pcVar12 = __file;
        if ((iVar5 == 0) && ((local_d8.st_mode & 0xf000) == 0xa000)) {
          if ((local_130 == (ulong *)0x0) &&
             (local_130 = FUN_001123f0(7,0,FUN_00106f60,FUN_00108950,FUN_00106fc0),
             local_130 == (ulong *)0x0)) goto LAB_0011294a;
          local_f8 = local_118;
          local_f0 = local_d8.st_ino;
          local_e8 = local_d8.st_dev;
          uVar8 = (*(code *)local_130[6])(&local_f8,local_130[2]);
          if (local_130[2] <= uVar8) {
            pcVar6 = (char *)FUN_00104d04();
            return pcVar6;
          }
          plVar14 = (long *)(uVar8 * 0x10 + *local_130);
          ppcVar16 = (char **)*plVar14;
          if (ppcVar16 == (char **)0x0) {
LAB_001127a5:
            pcVar6 = (char *)malloc(0x18);
            if (pcVar6 == (char *)0x0) goto LAB_0011294a;
            uVar9 = FUN_0010e640(local_118);
            *(undefined8 *)pcVar6 = uVar9;
            *(__ino_t *)(pcVar6 + 8) = local_d8.st_ino;
            *(__dev_t *)(pcVar6 + 0x10) = local_d8.st_dev;
            uVar9 = FUN_0010caa0((long *)local_130,(long)pcVar6,(long *)&local_f8);
            if ((int)uVar9 == -1) goto LAB_0011294a;
            if ((int)uVar9 == 0) {
              if (local_f8 == (char *)0x0) goto LAB_0011294a;
              if (local_f8 != pcVar6) {
                free(*(void **)pcVar6);
                free(pcVar6);
              }
            }
            pcVar17 = FUN_0010c3e0(__file,local_d8.st_size);
            if (pcVar17 != (char *)0x0) {
              sVar7 = strlen(pcVar17);
              sVar10 = strlen(param_1);
              if (local_108 == 0) {
                uVar8 = sVar7 + 1 + sVar10;
                local_108 = 0x1000;
                if (0xfff < uVar8) {
                  local_108 = uVar8;
                }
                local_110 = (char *)malloc(local_108);
joined_r0x00112b1c:
                if (local_110 == (char *)0x0) goto LAB_0011294a;
              }
              else {
                uVar8 = sVar7 + 1 + sVar10;
                if (local_108 < uVar8) {
                  local_110 = (char *)realloc(local_110,uVar8);
                  local_108 = uVar8;
                  goto joined_r0x00112b1c;
                }
              }
              memmove(local_110 + sVar7,param_1,sVar10 + 1);
              memcpy(local_110,pcVar17,sVar7);
              local_118 = local_110;
              pcVar6 = __file + 1;
              if (*pcVar17 == '/') {
                *__file = '/';
              }
              else {
                bVar1 = pcVar6 < pcVar18;
                pcVar6 = pcVar18;
                if ((bVar1) && (pcVar6 = pcVar18 + -1, __file < pcVar6)) {
                  do {
                    if (pcVar6[-1] == '/') break;
                    pcVar6 = pcVar6 + -1;
                  } while (__file != pcVar6);
                }
              }
              free(pcVar17);
              param_1 = local_110;
              goto LAB_00112684;
            }
            piVar13 = __errno_location();
            if (*piVar13 == 0xc) {
              free(local_110);
              pcVar6 = (char *)0x0;
              free(__file);
              FUN_0010c9b0(local_130);
              *piVar13 = 0xc;
              goto LAB_00112978;
            }
          }
          else {
            while (ppcVar16 != &local_f8) {
              cVar4 = (*(code *)local_130[7])(&local_f8);
              if (cVar4 != '\0') {
                if (*plVar14 == 0) goto LAB_001127a5;
                break;
              }
              plVar14 = (long *)plVar14[1];
              if (plVar14 == (long *)0x0) goto LAB_001127a5;
              ppcVar16 = (char **)*plVar14;
            }
          }
          cVar4 = pcVar11[1];
        }
        else {
LAB_00112684:
          cVar4 = *param_1;
          pcVar18 = pcVar6;
        }
      }
    } while (cVar4 != '\0');
  }
  else {
    pcVar6 = getcwd((char *)0x0,0);
    if (pcVar6 == (char *)0x0) {
      piVar13 = __errno_location();
      if (*piVar13 == 0xc) goto LAB_0011294a;
      goto LAB_00112978;
    }
    sVar7 = strlen(pcVar6);
    pcVar15 = pcVar6 + sVar7;
    pcVar18 = pcVar15;
    pcVar12 = pcVar6;
    if (sVar7 < 0x1000) {
      pcVar12 = (char *)realloc(pcVar6,0x1000);
      if (pcVar12 == (char *)0x0) goto LAB_0011294a;
      pcVar18 = pcVar12 + sVar7;
      pcVar15 = pcVar12 + 0x1000;
    }
    cVar4 = *param_1;
    if (cVar4 != '\0') goto LAB_00112547;
    local_130 = (ulong *)0x0;
    local_110 = (char *)0x0;
  }
  if ((pcVar12 + 1 < pcVar18) && (pcVar18[-1] == '/')) {
    pcVar11 = pcVar18;
    pcVar18 = pcVar18 + -1;
  }
  else {
    pcVar11 = pcVar18 + 1;
  }
  *pcVar18 = '\0';
  pcVar6 = pcVar12;
  if (pcVar11 != pcVar15) {
    sVar7 = ((long)pcVar18 - (long)pcVar12) + 1;
    if (((long)pcVar18 - (long)pcVar12 == -1) && (pcVar12 != (char *)0x0)) {
      pcVar6 = (char *)0x0;
      free(pcVar12);
    }
    else {
      pcVar6 = (char *)realloc(pcVar12,sVar7);
      if ((pcVar6 == (char *)0x0) && (sVar7 != 0)) {
LAB_0011294a:
                    // WARNING: Subroutine does not return
        FUN_0010dd70();
      }
    }
  }
  free(local_110);
  if (local_130 != (ulong *)0x0) {
    FUN_0010c9b0(local_130);
  }
LAB_00112978:
  if (local_40 == *(long *)(in_FS_OFFSET + 0x28)) {
    return pcVar6;
  }
                    // WARNING: Subroutine does not return
  __stack_chk_fail();
}
```

</details>

### Available Options

| Option | Description | Default |
|--------|-------------|---------|
| `output_dir` | Output directory path | "." |
| `base_name` | Base name for output files | program name |
| `create_c_file` | Create C implementation file (true/false) | true |
| `create_header_file` | Create header file (true/false) | false |
| `use_cpp_style_comments` | Use C++ style comments (true/false) | true |
| `emit_type_definitions` | Include type definitions (true/false) | true |
| `emit_referenced_globals` | Include global variables (true/false) | true |
| `function_tag_filters` | Function tags to filter by ("TAG1,TAG2") | "" |
| `function_tag_exclude` | Exclude (vs include) matching tags (true/false) | true |
| `address_set_str` | Address ranges to process ("0x1000-0x2000,0x3000") | null |
| `emit_function_declarations` | Include function prototypes (true/false) | true |
| `include_functions_only` | Include only named functions ("foo,bar,baz") | null |
| `run_decompiler_parameter_id` | Run Parameter ID analysis for better variable names (true/false) | true |

### Example Commands

**Basic usage with default options:**
```bash
$GHIDRA_INSTALL_DIR/analyzeHeadless ~/ghidra_projects MyProject -process Program.exe \
  -preScript ./cpp_exporter_headless.py
```

**Customized export:**
```bash
$GHIDRA_INSTALL_DIR/analyzeHeadless ~/ghidra_projects MyProject -process Program.exe \
  -preScript ./cpp_exporter_headless.py \
  output_dir exported_code \
  base_name program_src \
  create_header_file true \
  use_cpp_style_comments false \
  include_functions_only "main,init,cleanup"
```

**Export specific address range:**
```bash
$GHIDRA_INSTALL_DIR/analyzeHeadless ~/ghidra_projects MyProject -process Program.exe \
  -preScript ./cpp_exporter_headless.py \
  address_set_str "0x401000-0x402000"
```
