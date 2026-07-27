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
      "status": "in_progress",
      "conclusion": null,
      "created_at": "2026-07-26T14:53:24Z",
      "started_at": "2026-07-26T14:53:27Z",
      "completed_at": null,
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
          "status": "in_progress",
          "conclusion": null,
          "number": 15,
          "started_at": "2026-07-26T15:12:39Z",
          "completed_at": null
        },
        {
          "name": "Rename portable EXE for release",
          "status": "pending",
          "conclusion": null,
          "number": 28,
          "started_at": null,
          "completed_at": null
        },
        {
          "name": "Upload x64 Windows artifacts",
          "status": "pending",
          "conclusion": null,
          "number": 29,
          "started_at": null,
          "completed_at": null
        },
        {
          "name": "Upload x86 service artifacts",
          "status": "pending",
          "conclusion": null,
          "number": 30,
          "started_at": null,
          "completed_at": null
        },
        {
          "name": "Upload runtime logs (always)",
          "status": "pending",
          "conclusion": null,
          "number": 31,
          "started_at": null,
          "completed_at": null
        },
        {
          "name": "Upload to v3.1.1 Release (x64 only)",
          "status": "pending",
          "conclusion": null,
          "number": 32,
          "started_at": null,
          "completed_at": null
        },
        {
          "name": "Post Cache vcpkg installed packages",
          "status": "pending",
          "conclusion": null,
          "number": 61,
          "started_at": null,
          "completed_at": null
        },
        {
          "name": "Post Setup Flutter",
          "status": "pending",
          "conclusion": null,
          "number": 62,
          "started_at": null,
          "completed_at": null
        },
        {
          "name": "Post Cache Cargo registry",
          "status": "pending",
          "conclusion": null,
          "number": 63,
          "started_at": null,
          "completed_at": null
        },
        {
          "name": "Post Run actions/checkout@v4",
          "status": "pending",
          "conclusion": null,
          "number": 64,
          "started_at": null,
          "completed_at": null
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