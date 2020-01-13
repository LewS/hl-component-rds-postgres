CloudFormation do

  Description "#{external_parameters[:component_name]} - #{external_parameters[:component_version]}"

  tags = []
  tags << { Key: 'Environment', Value: Ref(:EnvironmentName) }
  tags << { Key: 'EnvironmentType', Value: Ref(:EnvironmentType) }

  extra_tags = external_parameters.fetch(:extra_tags, {})
  extra_tags.each { |key,value| tags << { Key: key, Value: value } }


  EC2_SecurityGroup "SecurityGroupRDS" do
    VpcId Ref('VPCId')
    GroupDescription FnJoin(' ', [ Ref(:EnvironmentName), external_parameters[:component_name], 'security group' ])
    SecurityGroupIngress sg_create_rules(external_parameters[:security_group], external_parameters[:ip_blocks])
    Tags tags + [{ Key: 'Name', Value: FnJoin('-', [ Ref(:EnvironmentName), external_parameters[:component_name], 'security-group' ])}]
    Metadata({
      cfn_nag: {
        rules_to_suppress: [
          { id: 'F1000', reason: 'specifying explicit egress rules unnecessary' }
        ]
      }
    })
  end

  RDS_DBSubnetGroup 'SubnetGroupRDS' do
    DBSubnetGroupDescription FnJoin(' ', [ Ref(:EnvironmentName), external_parameters[:component_name], 'subnet group' ])
    SubnetIds Ref('SubnetIds')
    Tags tags + [{ Key: 'Name', Value: FnJoin('-', [ Ref(:EnvironmentName), external_parameters[:component_name], 'subnet-group' ])}]
  end

  RDS_DBParameterGroup 'ParametersRDS' do
    Description FnJoin(' ', [ Ref(:EnvironmentName), external_parameters[:component_name], 'parameter group' ])
    Family external_parameters[:family]
    Parameters external_parameters[:parameters]
    Tags tags + [{ Key: 'Name', Value: FnJoin('-', [ Ref(:EnvironmentName), external_parameters[:component_name], 'parameter-group' ])}]
  end

  master_username = external_parameters.fetch(:master_username, '')
  master_password = external_parameters.fetch(:master_password, '')
  instance_username = !master_username.empty? ? master_username : FnJoin('', [ '{{resolve:ssm:', FnSub(external_parameters[:master_login]['username_ssm_param']), ':1}}' ])
  instance_password = !master_password.empty? ? master_password : FnJoin('', [ '{{resolve:ssm-secure:', FnSub(external_parameters[:master_login]['password_ssm_param']), ':1}}' ])

  maintenance_window = external_parameters.fetch(:maintenance_window, nil)
  kms_key_id = external_parameters.fetch(:kms_key_id, nil)
  storage_encrypted = external_parameters.fetch(:storage_encrypted, false)

  RDS_DBInstance 'RDS' do
    DeletionPolicy external_parameters[:deletion_policy]
    DBInstanceClass Ref('RDSInstanceType')
    AllocatedStorage Ref('RDSAllocatedStorage')
    StorageType 'gp2'
    Engine 'postgres'
    EngineVersion external_parameters[:engineVersion]
    DBParameterGroupName Ref('ParametersRDS')
    MasterUsername instance_username
    MasterUserPassword instance_password
    DBSnapshotIdentifier Ref('RDSSnapshotID')
    DBSubnetGroupName Ref('SubnetGroupRDS')
    VPCSecurityGroups [Ref('SecurityGroupRDS')]
    MultiAZ Ref('MultiAZ')
    PreferredMaintenanceWindow maintenance_window unless maintenance_window.nil?
    PubliclyAccessible external_parameters[:publicly_accessible]
    StorageEncrypted storage_encrypted
    KmsKeyId kms_key_id if (!kms_key_id.nil? && storage_encrypted)
    Tags  tags + [{ Key: 'Name', Value: FnJoin('-', [ Ref(:EnvironmentName), external_parameters[:component_name], 'instance' ])}]
    Metadata({
      cfn_nag: {
        rules_to_suppress: [
          { id: 'F23', reason: 'ignoring until further action is required' },
          { id: 'F24', reason: 'ignoring until further action is required' }
        ]
      }
    })
  end

  Route53_RecordSet('DatabaseIntHostRecord') do
    HostedZoneName FnJoin('', [ Ref('EnvironmentName'), '.', Ref('DnsDomain'), '.'])
    Name FnJoin('', [ 'postgres', '.', Ref('EnvironmentName'), '.', Ref('DnsDomain'), '.' ])
    Type 'CNAME'
    TTL 60
    ResourceRecords [ FnGetAtt('RDS','Endpoint.Address') ]
  end
end
