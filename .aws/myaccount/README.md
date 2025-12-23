# 自己需要建立 role
trust policy
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::459063348692:role/aws-reserved/sso.amazonaws.com/ap-northeast-1/AWSReservedSSO_cjc102-Route53-Z01780191-Editor_eff017d25a2dca6f"
            },
            "Action": "sts:AssumeRole",
            "Condition": {
                "StringEquals": {
                    "sts:ExternalId": "cjc102-route53-record-manager"
                }
            }
        }
    ]
}

permission policy
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowListRecordsInSpecificHostedZone",
            "Effect": "Allow",
            "Action": [
                "route53:ListResourceRecordSets"
            ],
            "Resource": "arn:aws:route53:::hostedzone/Z01780191CLMBHU6Y6729"
        },
        {
            "Sid": "AllowChangeRecordsInSpecificHostedZone",
            "Effect": "Allow",
            "Action": [
                "route53:ChangeResourceRecordSets"
            ],
            "Resource": "arn:aws:route53:::hostedzone/Z01780191CLMBHU6Y6729"
        },
        {
            "Sid": "AllowGetChangeStatus",
            "Effect": "Allow",
            "Action": [
                "route53:GetChange"
            ],
            "Resource": "*"
        }
    ]
}