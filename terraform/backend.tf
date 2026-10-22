# 상태 파일(tfstate)은 S3에 저장하고 같은 버킷의 잠금 파일로 동시 apply를 막는다.
# 버킷 이름은 계정 번호가 들어가서 저장소에 두지 않고 backend.hcl(커밋 제외)로 넘긴다.
#   cp backend.hcl.example backend.hcl   # 버킷 이름 입력
#   terraform init -backend-config=backend.hcl
# CI 검증은 terraform init -backend=false 라서 이 설정을 쓰지 않는다.
terraform {
  backend "s3" {
    key          = "aws/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
