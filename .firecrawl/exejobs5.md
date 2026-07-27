```json
{
  "total_count": 1,
  "jobs": [
    {
      "id": 89806783002,
      "run_id": 30207029210,
      "workflow_name": "Build LDesk Windows EXE",
      "head_branch": "3.1.1",
      "run_url": "https://api.github.com/repos/luoda2023/LUODA-v3.0.1/actions/runs/30207029210",
      "run_attempt": 1,
      "node_id": "CR_kwDOTWOwXc8AAAAU6ObCGg",
      "head_sha": "ac73aa11076f8ce7f9e27615d89734837ef4265a",
      "url": "https://api.github.com/repos/luoda2023/LUODA-v3.0.1/actions/jobs/89806783002",
      "html_url": "https://github.com/luoda2023/LUODA-v3.0.1/actions/runs/30207029210/job/89806783002",
      "status": "completed",
      "conclusion": "failure",
      "created_at": "2026-07-26T14:53:24Z",
      "started_at": "2026-07-26T14:53:27Z",
      "completed_at": "2026-07-26T15:31:07Z",
      "name": "build-exe (x64)",
      "steps": [
        {
          "name": "Set up job",
          "status": "completed",
          "conclusion": "success",
          "number": 1,
          "started_at": "2026-07-26T14:53:28Z",
          "completed_at": "2026-07-26T14:53:31Z"
        },
        {
          "name": "Run actions/checkout@v4",
          "status": "completed",
          "conclusion": "success",
          "number": 2,
          "started_at": "2026-07-26T14:53:31Z",
          "completed_at": "2026-07-26T14:53:35Z"
        },
        {
          "name": "Verify branded icon assets",
          "status": "completed",
          "conclusion": "success",
          "number": 3,
          "started_at": "2026-07-26T14:53:35Z",
          "completed_at": "2026-07-26T14:53:39Z"
        },
        {
          "name": "Cache Cargo registry",
          "status": "completed",
          "conclusion": "success",
          "number": 4,
          "started_at": "2026-07-26T14:53:39Z",
          "completed_at": "2026-07-26T14:53:51Z"
        },
        {
          "name": "Setup Flutter",
          "status": "completed",
          "conclusion": "success",
          "number": 5,
          "started_at": "2026-07-26T14:53:51Z",
          "completed_at": "2026-07-26T14:54:58Z"
        },
        {
          "name": "Setup Rust",
          "status": "completed",
          "conclusion": "success",
          "number": 6,
          "started_at": "2026-07-26T14:54:58Z",
          "completed_at": "2026-07-26T14:55:08Z"
        },
        {
          "name": "Install rustfmt",
          "status": "completed",
          "conclusion": "success",
          "number": 7,
          "started_at": "2026-07-26T14:55:08Z",
          "completed_at": "2026-07-26T14:55:09Z"
        },
        {
          "name": "Ensure correct cargo version",
          "status": "completed",
          "conclusion": "success",
          "number": 8,
          "started_at": "2026-07-26T14:55:09Z",
          "completed_at": "2026-07-26T14:55:09Z"
        },
        {
          "name": "Configure Git for private forks",
          "status": "completed",
          "conclusion": "success",
          "number": 9,
          "started_at": "2026-07-26T14:55:09Z",
          "completed_at": "2026-07-26T14:55:10Z"
        },
        {
          "name": "Generate FFI bridge",
          "status": "completed",
          "conclusion": "success",
          "number": 10,
          "started_at": "2026-07-26T14:55:10Z",
          "completed_at": "2026-07-26T15:01:25Z"
        },
        {
          "name": "Setup vcpkg",
          "status": "completed",
          "conclusion": "success",
          "number": 11,
          "started_at": "2026-07-26T15:01:25Z",
          "completed_at": "2026-07-26T15:01:55Z"
        },
        {
          "name": "Cache vcpkg installed packages",
          "status": "completed",
          "conclusion": "success",
          "number": 12,
          "started_at": "2026-07-26T15:01:55Z",
          "completed_at": "2026-07-26T15:02:02Z"
        },
        {
          "name": "Install vcpkg deps",
          "status": "completed",
          "conclusion": "success",
          "number": 13,
          "started_at": "2026-07-26T15:02:02Z",
          "completed_at": "2026-07-26T15:02:13Z"
        },
        {
          "name": "Build Rust",
          "status": "completed",
          "conclusion": "success",
          "number": 14,
          "started_at": "2026-07-26T15:02:13Z",
          "completed_at": "2026-07-26T15:12:39Z"
        },
        {
          "name": "Validate direct IP access",
          "status": "completed",
          "conclusion": "success",
          "number": 15,
          "started_at": "2026-07-26T15:12:39Z",
          "completed_at": "2026-07-26T15:30:36Z"
        },
        {
          "name": "Validate shared chat and UI contracts",
          "status": "completed",
          "conclusion": "failure",
          "number": 16,
          "started_at": "2026-07-26T15:30:36Z",
          "completed_at": "2026-07-26T15:31:03Z"
        },
        {
          "name": "Normalize Windows resource encoding",
          "status": "completed",
          "conclusion": "skipped",
          "number": 17,
          "started_at": "2026-07-26T15:31:03Z",
          "completed_at": "2026-07-26T15:31:03Z"
        },
        {
          "name": "Build Flutter Windows",
          "status": "completed",
          "conclusion": "skipped",
          "number": 18,
          "started_at": "2026-07-26T15:31:03Z",
          "completed_at": "2026-07-26T15:31:03Z"
        },
        {
          "name": "Include remote printer adapter",
          "status": "completed",
          "conclusion": "skipped",
          "number": 19,
          "started_at": "2026-07-26T15:31:03Z",
          "completed_at": "2026-07-26T15:31:03Z"
        },
        {
          "name": "Include signed virtual display driver",
          "status": "completed",
          "conclusion": "skipped",
          "number": 20,
          "started_at": "2026-07-26T15:31:03Z",
          "completed_at": "2026-07-26T15:31:03Z"
        },
        {
          "name": "Verify Flutter font assets",
          "status": "completed",
          "conclusion": "skipped",
          "number": 21,
          "started_at": "2026-07-26T15:31:03Z",
          "completed_at": "2026-07-26T15:31:03Z"
        },
        {
          "name": "Sign executable with LDesk icon",
          "status": "completed",
          "conclusion": "skipped",
          "number": 22,
          "started_at": "2026-07-26T15:31:03Z",
          "completed_at": "2026-07-26T15:31:03Z"
        },
        {
          "name": "Build portable packer",
          "status": "completed",
          "conclusion": "skipped",
          "number": 23,
          "started_at": "2026-07-26T15:31:03Z",
          "completed_at": "2026-07-26T15:31:03Z"
        },
        {
          "name": "Verify portable relaunch keeps the running instance intact",
          "status": "completed",
          "conclusion": "skipped",
          "number": 24,
          "started_at": "2026-07-26T15:31:03Z",
          "completed_at": "2026-07-26T15:31:03Z"
        },
        {
          "name": "Smoke test Windows main window responsiveness",
          "status": "completed",
          "conclusion": "skipped",
          "number": 25,
          "started_at": "2026-07-26T15:31:03Z",
          "completed_at": "2026-07-26T15:31:03Z"
        },
        {
          "name": "Verify Windows version metadata",
          "status": "completed",
          "conclusion": "skipped",
          "number": 26,
          "started_at": "2026-07-26T15:31:03Z",
          "completed_at": "2026-07-26T15:31:03Z"
        },
        {
          "name": "Build x64 installer",
          "status": "completed",
          "conclusion": "skipped",
          "number": 27,
          "started_at": "2026-07-26T15:31:03Z",
          "completed_at": "2026-07-26T15:31:03Z"
        },
        {
          "name": "Rename portable EXE for release",
          "status": "completed",
          "conclusion": "skipped",
          "number": 28,
          "started_at": "2026-07-26T15:31:03Z",
          "completed_at": "2026-07-26T15:31:03Z"
        },
        {
          "name": "Upload x64 Windows artifacts",
          "status": "completed",
          "conclusion": "skipped",
          "number": 29,
          "started_at": "2026-07-26T15:31:03Z",
          "completed_at": "2026-07-26T15:31:03Z"
        },
        {
          "name": "Upload x86 service artifacts",
          "status": "completed",
          "conclusion": "skipped",
          "number": 30,
          "started_at": "2026-07-26T15:31:03Z",
          "completed_at": "2026-07-26T15:31:03Z"
        },
        {
          "name": "Upload runtime logs (always)",
          "status": "completed",
          "conclusion": "success",
          "number": 31,
          "started_at": "2026-07-26T15:31:03Z",
          "completed_at": "2026-07-26T15:31:03Z"
        },
        {
          "name": "Upload to v3.1.1 Release (x64 only)",
          "status": "completed",
          "conclusion": "skipped",
          "number": 32,
          "started_at": "2026-07-26T15:31:03Z",
          "completed_at": "2026-07-26T15:31:03Z"
        },
        {
          "name": "Post Cache vcpkg installed packages",
          "status": "completed",
          "conclusion": "skipped",
          "number": 61,
          "started_at": "2026-07-26T15:31:03Z",
          "completed_at": "2026-07-26T15:31:03Z"
        },
        {
          "name": "Post Setup Flutter",
          "status": "completed",
          "conclusion": "success",
          "number": 62,
          "started_at": "2026-07-26T15:31:03Z",
          "completed_at": "2026-07-26T15:31:04Z"
        },
        {
          "name": "Post Cache Cargo registry",
          "status": "completed",
          "conclusion": "skipped",
          "number": 63,
          "started_at": "2026-07-26T15:31:04Z",
          "completed_at": "2026-07-26T15:31:04Z"
        },
        {
          "name": "Post Run actions/checkout@v4",
          "status": "completed",
          "conclusion": "success",
          "number": 64,
          "started_at": "2026-07-26T15:31:04Z",
          "completed_at": "2026-07-26T15:31:05Z"
        },
        {
          "name": "Complete job",
          "status": "completed",
          "conclusion": "success",
          "number": 65,
          "started_at": "2026-07-26T15:31:05Z",
          "completed_at": "2026-07-26T15:31:05Z"
        }
      ],
      "check_run_url": "https://api.github.com/repos/luoda2023/LUODA-v3.0.1/check-runs/89806783002",
      "labels": [
        "windows-2022"
      ],
      "runner_id": 1000018024,
      "runner_name": "GitHub Actions 1000018024",
      "runner_group_id": 0,
      "runner_group_name": "GitHub Actions"
    }
  ]
}

```