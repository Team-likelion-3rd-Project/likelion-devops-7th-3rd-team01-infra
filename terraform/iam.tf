# 노드 IAM 역할: SSM 접속 + (선택) Bedrock 호출. 액세스 키를 노드·Secret에 두지 않는다.
resource "aws_iam_role" "node" {
  name_prefix = "team01-k8s-node-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# 백엔드 담당이 만들어 검증한 Bedrock 호출 정책을 그대로 붙인다 (빈 값이면 생략)
data "aws_iam_policy" "bedrock" {
  count = var.bedrock_policy_name == "" ? 0 : 1
  name  = var.bedrock_policy_name
}

resource "aws_iam_role_policy_attachment" "bedrock" {
  count      = var.bedrock_policy_name == "" ? 0 : 1
  role       = aws_iam_role.node.name
  policy_arn = data.aws_iam_policy.bedrock[0].arn
}

resource "aws_iam_instance_profile" "node" {
  name_prefix = "team01-k8s-node-"
  role        = aws_iam_role.node.name
}
