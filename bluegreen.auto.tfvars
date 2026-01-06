# =============================================================================
# Blue-Green Deployment Configuration
# =============================================================================

# -----------------------------------------------------------------------------
# Blue Environment
# -----------------------------------------------------------------------------

blue_ecs_desired_count = 2    # Blue ECS 任務數量 (0 = standby)
blue_ecs_min_capacity  = 2    # Blue Auto Scaling 最小值 (0 = 可縮至零)
blue_ecs_max_capacity  = 10   # Blue Auto Scaling 最大值
blue_image_tag         = "v3" # Blue Docker Image Tag

# -----------------------------------------------------------------------------
# Green Environment
# -----------------------------------------------------------------------------

green_ecs_desired_count = 2    # Green ECS 任務數量 (0 = standby)
green_ecs_min_capacity  = 2    # Green Auto Scaling 最小值 (0 = 可縮至零)
green_ecs_max_capacity  = 10   # Green Auto Scaling 最大值
green_image_tag         = "v3" # Green Docker Image Tag

# -----------------------------------------------------------------------------
# ALB Traffic Weights (blue_weight + green_weight = 100)
# -----------------------------------------------------------------------------

blue_weight  = 0   # Blue 流量權重 (0-100)
green_weight = 100 # Green 流量權重 (0-100)

# =============================================================================
# Usage Examples:
# =============================================================================
#
# Blue 正常運行, Green 待命:
#   blue_ecs_desired_count = 2, blue_weight = 100
#   green_ecs_desired_count = 0, green_weight = 0
#
# 啟動 Green 測試 (10% 流量):
#   blue_ecs_desired_count = 2, blue_weight = 90
#   green_ecs_desired_count = 2, green_weight = 10
#
# 完全切換到 Green, Blue 進入待命:
#   blue_ecs_desired_count = 0, blue_weight = 0
#   green_ecs_desired_count = 2, green_weight = 100
# =============================================================================

# =============================================================================
# Canary Deployment Configuration (金絲雀部署)
# =============================================================================

canary_enabled       = true # 啟用金絲雀部署
pre_deploy_wait_sec  = 120  # 前搖時間：等待新部署完成 (秒)
canary_percentage    = 10   # 金絲雀初始流量比例 (0-50%)
canary_duration_sec  = 180  # 金絲雀觀察時間 (秒)
full_deploy_wait_sec = 120  # 全部署後等待時間 (秒)
rollback_window_sec  = 60   # 後悔回滾視窗 (秒)

