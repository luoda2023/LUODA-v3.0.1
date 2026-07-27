```json
{
  "total_count": 1,
  "jobs": [
    {
      "id": 89876300473,
      "run_id": 30233376829,
      "workflow_name": "Build LDesk Windows EXE",
      "head_branch": "3.1.1",
      "run_url": "https://api.github.com/repos/luoda2023/LUODA-v3.0.1/actions/runs/30233376829",
      "run_attempt": 1,
      "node_id": "CR_kwDOTWOwXc8AAAAU7QuCuQ",
      "head_sha": "63cc7fd1d1071a94ab727020af65d2af8e049c7d",
      "url": "https://api.github.com/repos/luoda2023/LUODA-v3.0.1/actions/jobs/89876300473",
      "html_url": "https://github.com/luoda2023/LUODA-v3.0.1/actions/runs/30233376829/job/89876300473",
      "status": "in_progress",
      "conclusion": null,
      "created_at": "2026-07-27T02:56:57Z",
      "started_at": "2026-07-27T02:57:00Z",
      "completed_at": null,
      "name": "build-exe (x64)",
      "steps": [
        {
          "name": "Set up job",
          "status": "completed",
          "conclusion": "success",
          "number": 1,
          "started_at": "2026-07-27T02:57:01Z",
          "completed_at": "2026-07-27T02:57:03Z"
        },
        {
          "name": "Run actions/checkout@v4",
          "status": "completed",
          "conclusion": "success",
          "number": 2,
          "started_at": "2026-07-27T02:57:03Z",
          "completed_at": "2026-07-27T02:57:08Z"
        },
        {
          "name": "Verify branded icon assets",
          "status": "completed",
          "conclusion": "success",
          "number": 3,
          "started_at": "2026-07-27T02:57:08Z",
          "completed_at": "2026-07-27T02:57:09Z"
        },
        {
          "name": "Cache Cargo registry",
          "status": "completed",
          "conclusion": "success",
          "number": 4,
          "started_at": "2026-07-27T02:57:09Z",
          "completed_at": "2026-07-27T02:57:19Z"
        },
        {
          "name": "Setup Flutter",
          "status": "completed",
          "conclusion": "success",
          "number": 5,
          "started_at": "2026-07-27T02:57:19Z",
          "completed_at": "2026-07-27T02:58:23Z"
        },
        {
          "name": "Setup Rust",
          "status": "completed",
          "conclusion": "success",
          "number": 6,
          "started_at": "2026-07-27T02:58:23Z",
          "completed_at": "2026-07-27T02:58:36Z"
        },
        {
          "name": "Install rustfmt",
          "status": "completed",
          "conclusion": "success",
          "number": 7,
          "started_at": "2026-07-27T02:58:36Z",
          "completed_at": "2026-07-27T02:58:42Z"
        },
        {
          "name": "Ensure correct cargo version",
          "status": "completed",
          "conclusion": "success",
          "number": 8,
          "started_at": "2026-07-27T02:58:42Z",
          "completed_at": "2026-07-27T02:58:43Z"
        },
        {
          "name": "Configure Git for private forks",
          "status": "completed",
          "conclusion": "success",
          "number": 9,
          "started_at": "2026-07-27T02:58:43Z",
          "completed_at": "2026-07-27T02:58:43Z"
        },
        {
          "name": "Generate FFI bridge",
          "status": "completed",
          "conclusion": "success",
          "number": 10,
          "started_at": "2026-07-27T02:58:43Z",
          "completed_at": "2026-07-27T03:06:38Z"
        },
        {
          "name": "Setup vcpkg",
          "status": "completed",
          "conclusion": "success",
          "number": 11,
          "started_at": "2026-07-27T03:06:38Z",
          "completed_at": "2026-07-27T03:07:14Z"
        },
        {
          "name": "Cache vcpkg installed packages",
          "status": "completed",
          "conclusion": "success",
          "number": 12,
          "started_at": "2026-07-27T03:07:14Z",
          "completed_at": "2026-07-27T03:07:18Z"
        },
        {
          "name": "Install vcpkg deps",
          "status": "completed",
          "conclusion": "success",
          "number": 13,
          "started_at": "2026-07-27T03:07:18Z",
          "completed_at": "2026-07-27T03:07:29Z"
        },
        {
          "name": "Build Rust",
          "status": "completed",
          "conclusion": "success",
          "number": 14,
          "started_at": "2026-07-27T03:07:29Z",
          "completed_at": "2026-07-27T03:21:37Z"
        },
        {
          "name": "Validate direct IP access",
          "status": "in_progress",
          "conclusion": null,
          "number": 15,
          "started_at": "2026-07-27T03:21:37Z",
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
      "check_run_url": "https://api.github.com/repos/luoda2023/LUODA-v3.0.1/check-runs/89876300473",
      "labels": [
        "windows-2022"
      ],
      "runner_id": 1000018046,
      "runner_name": "GitHub Actions 1000018046",
      "runner_group_id": 0,
      "runner_group_name": "GitHub Actions"
    }
  ]
}

```