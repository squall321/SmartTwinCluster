/**
 * SAML IdP Configuration File
 * User database for authentication
 */

module.exports = {
  user: {
    "koopark@hpc.local": {
      password: "admin123",
      email: "koopark@hpc.local",
      userName: "koopark",
      firstName: "Kook Jin",
      lastName: "Park",
      displayName: "박국진 관리자",
      groups: "HPC-Admins",
      department: "IT관리팀"
    },
    "admin@hpc.local": {
      password: "admin123",
      email: "admin@hpc.local",
      userName: "admin",
      firstName: "시스템",
      lastName: "관리자",
      displayName: "시스템 관리자",
      groups: "HPC-Admins",
      department: "IT관리팀"
    },
    "dx_user@hpc.local": {
      password: "password123",
      email: "dx_user@hpc.local",
      userName: "dx_user",
      firstName: "DX",
      lastName: "사용자",
      displayName: "DX 사용자",
      groups: "DX-Users",
      department: "디지털전환팀"
    },
    "caeg_user@hpc.local": {
      password: "password123",
      email: "caeg_user@hpc.local",
      userName: "caeg_user",
      firstName: "CAEG",
      lastName: "사용자",
      displayName: "CAEG 사용자",
      groups: "CAEG-Users",
      department: "CAE해석팀"
    }
  },
  metadata: [
    {id: "email", optional: false, displayName: 'E-Mail Address', description: 'The e-mail address of the user', multiValue: false},
    {id: "userName", optional: false, displayName: 'User Name', description: 'The username of the user', multiValue: false},
    {id: "firstName", optional: false, displayName: 'First Name', description: 'The first name of the user', multiValue: false},
    {id: "lastName", optional: false, displayName: 'Last Name', description: 'The last name of the user', multiValue: false},
    {id: "displayName", optional: true, displayName: 'Display Name', description: 'The display name of the user', multiValue: false},
    {id: "groups", optional: true, displayName: 'Groups', description: 'Group memberships of the user', multiValue: false}
  ]
};
